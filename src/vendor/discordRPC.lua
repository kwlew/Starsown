--[[
    A from-scratch Discord Rich Presence client for LÖVE2D. No external
    Discord libraries -- talks directly to Discord's local IPC transport:
      - Windows: named pipe  \\.\pipe\discord-ipc-N
      - macOS/Linux: Unix domain socket  $XDG_RUNTIME_DIR/discord-ipc-N
                     (falls back to $TMPDIR, $TMP, $TEMP, /tmp)

    Needs LuaJIT's `ffi`/`bit` (ship with LÖVE) and love.system.getOS() for
    platform detection (falls back to jit.os outside LÖVE).

    Discord IPC protocol (informally documented, stable for years): each
    message is [4B opcode LE][4B length LE][JSON payload]. Opcodes: 0
    HANDSHAKE, 1 FRAME, 2 CLOSE, 3 PING, 4 PONG. Client sends opcode 0 with
    {v=1, client_id}; Discord replies opcode 1 with a DISPATCH/READY event;
    after that opcode 1 frames carry commands like SET_ACTIVITY.

    USAGE: nothing else in the game talks to this directly --
    services/presence.lua owns the connection, payload shape, and retry.

        RPC.initialize(applicationId, { onError = fn(code, detail) })  -- once, at load
        RPC.update(dt)                 -- every frame; drives connect + retry
        RPC.isReady()                  -- true once Discord has sent READY
        RPC.setActivity(activity)      -- details/state/timestamps/assets
        RPC.clearActivity()
        RPC.shutdown()                 -- on quit, so the presence clears now
        RPC.getLastError()
        RPC.state()                    -- "disconnected" | "handshaking" | "connected"

    CAVEATS:
      - Only local Rich Presence (details/state/images/timestamps/buttons).
        Join/Spectate/ask-to-join needs ACTIVITY_JOIN/ACTIVITY_SPECTATE
        handling and a lobby system -- not included.
      - Requires LuaJIT, not plain Lua -- `ffi` doesn't exist elsewhere.
      - If Discord isn't running, RPC.update() just retries quietly every
        few seconds; the game never blocks or crashes waiting for it. Anything
        worse (Discord refusing the app id, an error reply, a broken pipe)
        goes to onError as a short code plus detail, then reconnects.
      - pid is sent so Discord can clear the presence if the game dies
        without calling RPC.shutdown().
--]]

local ffi = require("ffi")

local isWindows, isMac, isLinux = false, false, false

if love and love.system then
    local osName = love.system.getOS()
    isWindows = (osName == "Windows")
    isMac     = (osName == "OS X")
    isLinux   = (osName == "Linux")
else
    -- fallback if ever loaded outside LÖVE (e.g. a quick luajit test script)
    isWindows = (jit and jit.os == "Windows")
    isMac     = (jit and jit.os == "OSX")
    isLinux   = (jit and jit.os == "Linux")
end

-- tiny JSON encoder/decoder, just enough for Discord's payloads

local json = {}

---@param t table
---@return boolean # true when the keys are exactly 1..n
local function isArray(t)
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" then return false end
        n = n + 1
    end
    return n == #t
end

local escapeMap = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }

---@param s string
---@return string
local function escapeStr(s)
    return (s:gsub('[%z\1-\31\\"]', function(c)
        return escapeMap[c] or string.format('\\u%04x', c:byte())
    end))
end

--- anything that isn't a string, number, boolean, nil or table encodes as null
---@param v any
---@return string
function json.encode(v)
    local t = type(v)
    if t == "string" then
        return '"' .. escapeStr(v) .. '"'
    elseif t == "number" or t == "boolean" then
        return tostring(v)
    elseif t == "nil" then
        return "null"
    elseif t == "table" then
        if isArray(v) then
            local parts = {}
            for i, item in ipairs(v) do parts[i] = json.encode(item) end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local parts = {}
            for k, val in pairs(v) do
                if val ~= nil then
                    parts[#parts + 1] = '"' .. escapeStr(tostring(k)) .. '":' .. json.encode(val)
                end
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return "null"
end

--- enough of a parser for Discord's replies. Returns nil rather than raising on
-- malformed input -- a bad frame shouldn't take the game down.
---@param str any # the JSON text
---@return any|nil
function json.decode(str)
    local pos = 1
    local parseValue

    --- advances `pos` past any whitespace
    local function skipWhitespace()
        local _, e = str:find("^%s*", pos)
        pos = e + 1
    end

    --- \u escapes past ASCII become "?": Discord's replies are ASCII in practice,
    -- and nothing here reads the text back out
    ---@return string
    local function parseString()
        pos = pos + 1
        local startPos = pos
        local buf = {}
        while true do
            local c = str:sub(pos, pos)
            if c == "" then break end
            if c == '"' then
                buf[#buf + 1] = str:sub(startPos, pos - 1)
                pos = pos + 1
                break
            elseif c == "\\" then
                buf[#buf + 1] = str:sub(startPos, pos - 1)
                local nextC = str:sub(pos + 1, pos + 1)
                local map = { n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
                if map[nextC] then
                    buf[#buf + 1] = map[nextC]
                    pos = pos + 2
                elseif nextC == "u" then
                    local hex = str:sub(pos + 2, pos + 5)
                    local code = tonumber(hex, 16) or 63
                    buf[#buf + 1] = (code < 128) and string.char(code) or "?"
                    pos = pos + 6
                else
                    pos = pos + 2
                end
                startPos = pos
            else
                pos = pos + 1
            end
        end
        return table.concat(buf)
    end

    ---@return number|nil
    local function parseNumber()
        local s, e = str:find("^%-?%d+%.?%d*[eE]?[+%-]?%d*", pos)
        local numStr = str:sub(s, e)
        pos = e + 1
        return tonumber(numStr)
    end

    ---@return table
    local function parseObject()
        pos = pos + 1
        local obj = {}
        skipWhitespace()
        if str:sub(pos, pos) == "}" then pos = pos + 1; return obj end
        while true do
            skipWhitespace()
            local key = parseString()
            skipWhitespace()
            pos = pos + 1 -- skip ':'
            skipWhitespace()
            obj[key] = parseValue()
            skipWhitespace()
            local c = str:sub(pos, pos)
            pos = pos + 1
            if c == "}" then break end
        end
        return obj
    end

    ---@return any[]
    local function parseArray()
        pos = pos + 1
        local arr = {}
        skipWhitespace()
        if str:sub(pos, pos) == "]" then pos = pos + 1; return arr end
        while true do
            skipWhitespace()
            arr[#arr + 1] = parseValue()
            skipWhitespace()
            local c = str:sub(pos, pos)
            pos = pos + 1
            if c == "]" then break end
        end
        return arr
    end

    --- any JSON value, dispatched on its first character
    parseValue = function()
        skipWhitespace()
        local c = str:sub(pos, pos)
        if c == '"' then return parseString()
        elseif c == "{" then return parseObject()
        elseif c == "[" then return parseArray()
        elseif c == "t" then pos = pos + 4; return true
        elseif c == "f" then pos = pos + 5; return false
        elseif c == "n" then pos = pos + 4; return nil
        else return parseNumber()
        end
    end

    local ok, result = pcall(parseValue)
    if ok then return result end
    return nil
end

-- frame packing helpers (4-byte little-endian uint32 headers)

---@param n integer
---@return string # 4 bytes, little endian
local function packU32LE(n)
    return string.char(
        n % 256,
        math.floor(n / 256) % 256,
        math.floor(n / 65536) % 256,
        math.floor(n / 16777216) % 256
    )
end

---@param s string
---@param offset integer # 1-based
---@return integer
local function unpackU32LE(s, offset)
    local b1, b2, b3, b4 = s:byte(offset, offset + 3)
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

-- Pipe: platform-specific transport (Windows named pipe / Unix socket)

--- The transport, one implementation per platform below. Both provide the same
-- three methods: write(data) -> ok, err; readAvailable() -> whatever is
-- waiting ("" if nothing) or nil, err once closed; and close().
local Pipe = {}
Pipe.__index = Pipe
local getCurrentPid -- filled in per-platform below

if isWindows then

    ffi.cdef[[
        typedef void* HANDLE;
        typedef unsigned long DWORD;
        typedef int BOOL;
        typedef unsigned short WCHAR;

        HANDLE CreateFileW(const WCHAR* lpFileName, DWORD dwDesiredAccess, DWORD dwShareMode,
                            void* lpSecurityAttributes, DWORD dwCreationDisposition,
                            DWORD dwFlagsAndAttributes, HANDLE hTemplateFile);
        BOOL ReadFile(HANDLE hFile, void* lpBuffer, DWORD nNumberOfBytesToRead,
                      DWORD* lpNumberOfBytesRead, void* lpOverlapped);
        BOOL WriteFile(HANDLE hFile, const void* lpBuffer, DWORD nNumberOfBytesToWrite,
                       DWORD* lpNumberOfBytesWritten, void* lpOverlapped);
        BOOL CloseHandle(HANDLE hObject);
        BOOL PeekNamedPipe(HANDLE hNamedPipe, void* lpBuffer, DWORD nBufferSize,
                           DWORD* lpBytesRead, DWORD* lpTotalBytesAvail, DWORD* lpBytesLeftThisMessage);
        DWORD GetCurrentProcessId(void);
        DWORD GetLastError(void);
    ]]

    local bit = require("bit")
    local kernel32 = ffi.load("kernel32")
    local INVALID_HANDLE_VALUE = ffi.cast("HANDLE", -1)
    local GENERIC_READ  = 0x80000000
    local GENERIC_WRITE = 0x40000000
    local OPEN_EXISTING = 3

    --- sent with every activity, so Discord can clear the presence if the game
    -- dies without calling shutdown()
    getCurrentPid = function() return tonumber(kernel32.GetCurrentProcessId()) end

    --- UTF-16 for CreateFileW; the paths here are ASCII, so this widens byte by byte
    ---@param s string
    ---@return ffi.cdata*
    local function toWideString(s)
        local buf = ffi.new("WCHAR[?]", #s + 1)
        for i = 1, #s do buf[i - 1] = s:byte(i) end
        buf[#s] = 0
        return buf
    end

    --- tries discord-ipc-0 through -9; nil when none of them answer
    ---@return table|nil
    function Pipe.connect()
        for i = 0, 9 do
            local path = "\\\\.\\pipe\\discord-ipc-" .. i
            local handle = kernel32.CreateFileW(toWideString(path),
                bit.bor(GENERIC_READ, GENERIC_WRITE), 0, nil, OPEN_EXISTING, 0, nil)
            if handle ~= INVALID_HANDLE_VALUE then
                return setmetatable({ handle = handle }, Pipe)
            end
        end
        return nil
    end

    ---@param call string
    ---@return string
    local function lastError(call)
        return ("%s failed (Windows error %d)"):format(call, tonumber(kernel32.GetLastError()))
    end

    ---@param data string
    ---@return boolean sent
    ---@return string? err
    function Pipe:write(data)
        local written = ffi.new("DWORD[1]")
        if kernel32.WriteFile(self.handle, data, #data, written, nil) == 0 then return false, lastError("WriteFile") end
        return true
    end

    --- whatever is waiting, without blocking: "" when nothing is, nil + why
    -- once the pipe is broken (Discord closed it)
    ---@return string|nil
    ---@return string? err
    function Pipe:readAvailable()
        local totalAvail = ffi.new("DWORD[1]")
        if kernel32.PeekNamedPipe(self.handle, nil, 0, nil, totalAvail, nil) == 0 then
            return nil, lastError("PeekNamedPipe")
        end
        local avail = tonumber(totalAvail[0])
        if avail == 0 then return "" end
        local buf = ffi.new("char[?]", avail)
        local readCount = ffi.new("DWORD[1]")
        if kernel32.ReadFile(self.handle, buf, avail, readCount, nil) == 0 then return nil, lastError("ReadFile") end
        return ffi.string(buf, tonumber(readCount[0]))
    end

    --- releases the handle
    function Pipe:close()
        kernel32.CloseHandle(self.handle)
    end

elseif isLinux or isMac then

    -- sockaddr_un differs: Linux is a 2-byte family then 108 path bytes,
    -- Darwin a 1-byte length, a 1-byte family, then 104
    ffi.cdef(isMac
        and "struct sockaddr_un { uint8_t sun_len; uint8_t sun_family; char sun_path[104]; };"
        or  "struct sockaddr_un { unsigned short sun_family; char sun_path[108]; };")
    ffi.cdef[[
        int socket(int domain, int type, int protocol);
        int connect(int sockfd, const struct sockaddr_un *addr, unsigned int addrlen);
        long read(int fd, void *buf, unsigned long count);
        long write(int fd, const void *buf, unsigned long count);
        int close(int fd);
        int fcntl(int fd, int cmd, int arg);
        int getpid(void);
        long send(int fd, const void *buf, unsigned long len, int flags);
        int setsockopt(int fd, int level, int optname, const void *optval, unsigned int optlen);
        char *strerror(int errnum);
    ]]

    local bit = require("bit")
    local C = ffi.C
    local AF_UNIX     = 1
    local SOCK_STREAM = 1
    local F_GETFL     = 3
    local F_SETFL     = 4
    local O_NONBLOCK  = isMac and 0x0004 or 0x800 -- differs between Linux and Darwin libc
    local EAGAIN      = isMac and 35 or 11 -- "nothing to read yet" on a non-blocking socket
    local SUN_PATH_MAX = isMac and 104 or 108 -- including the terminating NUL
    -- a write to a socket Discord has closed raises SIGPIPE, whose default
    -- action kills the whole game: Linux opts out per call, macOS per socket
    local MSG_NOSIGNAL = isMac and 0 or 0x4000
    local SOL_SOCKET, SO_NOSIGPIPE = 0xffff, 0x1022

    ---@param call string
    ---@return string
    local function lastError(call)
        local errno = ffi.errno()
        return ("%s failed: %s (errno %d)"):format(call, ffi.string(C.strerror(errno)), errno)
    end

    --- sent with every activity, so Discord can clear the presence if the game
    -- dies without calling shutdown()
    getCurrentPid = function() return tonumber(C.getpid()) end

    -- sandboxed Discord installs keep their socket in a subfolder of the usual place
    local SANDBOXES = { "", "/app/com.discordapp.Discord", "/app/com.discordapp.DiscordCanary", "/snap.discord" }

    --- where Discord's socket may live, best guess first.
    -- STARSOWN_DISCORD_IPC_DIR replaces the search outright: for an install
    -- that keeps its socket somewhere unusual, or a fake Discord in a test.
    ---@return string[]
    local function candidateDirs()
        local override = os.getenv("STARSOWN_DISCORD_IPC_DIR")
        if override and override ~= "" then return { override } end
        local dirs = {}
        local bases = {}
        for _, name in ipairs({ "XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP" }) do
            local v = os.getenv(name)
            if v and v ~= "" then bases[#bases + 1] = v end
        end
        bases[#bases + 1] = "/tmp"
        for _, base in ipairs(bases) do
            for _, sandbox in ipairs(SANDBOXES) do dirs[#dirs + 1] = base .. sandbox end
        end
        return dirs
    end

    --- tries discord-ipc-0 through -9 in every candidate directory, and switches
    -- the socket it finds to non-blocking; nil when none of them answer
    ---@return table|nil
    function Pipe.connect()
        for _, dir in ipairs(candidateDirs()) do
            for i = 0, 9 do
                local path = dir .. "/discord-ipc-" .. i
                -- ffi.copy doesn't bounds-check: a path that doesn't fit would
                -- overrun sun_path and corrupt the heap, and can't be a socket anyway
                local fd = #path < SUN_PATH_MAX and C.socket(AF_UNIX, SOCK_STREAM, 0) or -1
                if fd >= 0 then
                    local addr = ffi.new("struct sockaddr_un")
                    -- sockaddr_un's fields come from the ffi.cdef string above, invisible
                    -- to static analysis, hence the disables below.
                    ---@diagnostic disable-next-line: inject-field
                    addr.sun_family = AF_UNIX
                    ---@diagnostic disable-next-line: inject-field
                    if isMac then addr.sun_len = ffi.sizeof(addr) end
                    ---@diagnostic disable-next-line: undefined-field
                    ffi.copy(addr.sun_path, path)
                    if C.connect(fd, addr, ffi.sizeof(addr)) == 0 then
                        local flags = C.fcntl(fd, F_GETFL, 0)
                        C.fcntl(fd, F_SETFL, bit.bor(flags, O_NONBLOCK))
                        if isMac then
                            C.setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, ffi.new("int[1]", 1), ffi.sizeof("int"))
                        end
                        return setmetatable({ fd = fd, path = path }, Pipe)
                    else
                        C.close(fd)
                    end
                end
            end
        end
        return nil
    end

    ---@param data string
    ---@return boolean sent
    ---@return string? err
    function Pipe:write(data)
        local sent = 0
        while sent < #data do
            local n = C.send(self.fd, ffi.cast("const char*", data) + sent, #data - sent, MSG_NOSIGNAL)
            if n < 0 then return false, lastError("send") end
            sent = sent + tonumber(n)
        end
        return true
    end

    --- whatever is waiting, without blocking: "" when nothing is, nil + why
    -- once the socket is closed. read() returning 0 is Discord hanging up,
    -- which is not the same thing as -1/EAGAIN, "nothing yet".
    ---@return string|nil
    ---@return string? err
    function Pipe:readAvailable()
        local chunks = {}
        local buf = ffi.new("char[4096]")
        while true do
            local n = tonumber(C.read(self.fd, buf, 4096))
            if n > 0 then
                chunks[#chunks + 1] = ffi.string(buf, n)
                if n < 4096 then break end
            elseif n == 0 then
                return nil, "Discord closed the socket"
            elseif ffi.errno() == EAGAIN then
                break
            else
                return nil, lastError("read")
            end
        end
        return table.concat(chunks)
    end

    --- closes the socket
    function Pipe:close()
        C.close(self.fd)
    end

else
    error("discordrpc.lua: unsupported platform")
end

-- Connection: buffers raw bytes into complete frames

local Connection = {}
Connection.__index = Connection

---@param pipe table
---@return table
function Connection.new(pipe)
    return setmetatable({ pipe = pipe, buffer = "" }, Connection)
end

--- reads whatever is waiting into the buffer, without blocking
---@return boolean ok
---@return string? err # why the connection is gone
function Connection:pump()
    local chunk, err = self.pipe:readAvailable()
    if not chunk then return false, err end
    self.buffer = self.buffer .. chunk
    return true
end

--- one complete frame, or nil while the buffer holds only part of one
---@return integer|nil opcode
---@return string? payload
function Connection:popFrame()
    if #self.buffer < 8 then return nil end
    local opcode = unpackU32LE(self.buffer, 1)
    local length = unpackU32LE(self.buffer, 5)
    if #self.buffer < 8 + length then return nil end
    local payload = self.buffer:sub(9, 8 + length)
    self.buffer = self.buffer:sub(9 + length)
    return opcode, payload
end

---@param opcode integer # 0 HANDSHAKE, 1 FRAME, 2 CLOSE, 3 PING, 4 PONG
---@param payloadStr string
---@return boolean sent
---@return string? err
function Connection:sendFrame(opcode, payloadStr)
    return self.pipe:write(packU32LE(opcode) .. packU32LE(#payloadStr) .. payloadStr)
end

--- closes the underlying pipe; safe to call on one that's already broken
function Connection:close()
    pcall(self.pipe.close, self.pipe)
end

-- Public API

local RPC = {
    lastError = nil,
}

local clientId = nil
local onError = nil
local conn = nil
local state = "disconnected" -- disconnected -> handshaking -> connected
local retryTimer = 0
local handshakeTimer = 0 -- time spent in "handshaking"; past HANDSHAKE_TIMEOUT, treated as stuck
local nonceCounter = 0

local HANDSHAKE_TIMEOUT = 8 -- local IPC: a healthy Discord answers in well under a second
local HANDSHAKE_RETRY_DELAY = 2 -- shorter than the cold-start backoff below -- a stuck handshake
-- means Discord IS reachable, so a prompt retry is more likely to land

---@return string # unique per message, which is how a reply is matched to its command
local function nextNonce()
    nonceCounter = nonceCounter + 1
    return tostring(os.time()) .. "-" .. nonceCounter
end

--- records the app id and arms the connect; update() does the connecting
---@param discordApplicationId string
---@param opts? table # { onError = fun(code: string, detail: string) } -- told about anything worse than "Discord isn't running"
function RPC.initialize(discordApplicationId, opts)
    clientId = discordApplicationId
    onError = opts and opts.onError
    state = "disconnected"
    retryTimer = 0
    handshakeTimer = 0
end

---@param code string # short and stable, e.g. "DC-CLOSED-4000"
---@param detail string
local function report(code, detail)
    RPC.lastError = code .. ": " .. tostring(detail)
    if onError then onError(code, tostring(detail)) end
end

--- drops the connection (closing it, so nothing leaks) and schedules the
-- next attempt; `code` is the reason, when there is one worth reporting
---@param code? string
---@param detail? string
---@param retryIn? number # seconds
local function disconnect(code, detail, retryIn)
    if conn then conn:close() end
    conn = nil
    state = "disconnected"
    retryTimer = retryIn or 5
    if code then report(code, detail) end
end

--- one attempt at the local IPC socket, sending the handshake if it opens. A
-- socket that isn't there is silent -- Discord simply may not be running yet.
local function tryConnect()
    local pipe = Pipe.connect()
    if not pipe then return end
    conn = Connection.new(pipe)
    local sent, err = conn:sendFrame(0, json.encode({ v = 1, client_id = clientId }))
    if not sent then return disconnect("DC-IO", "handshake: " .. tostring(err)) end
    state = "handshaking"
    handshakeTimer = 0
end

---@param data any # a decoded CLOSE or ERROR payload
---@return string # "code: message", whatever of it is there, whatever of it is there
local function describe(data)
    if type(data) ~= "table" then return "no details" end
    local code, message = data.code, data.message
    if code and message then return tostring(code) .. ": " .. tostring(message) end
    return tostring(message or code or "no details")
end

---@param opcode integer
---@param payload string
local function handleFrame(opcode, payload)
    if opcode == 1 then
        local msg = json.decode(payload)
        if msg then
            if msg.evt == "READY" then
                state = "connected"
            elseif msg.evt == "ERROR" then
                report("DC-ERROR", (msg.cmd and (msg.cmd .. " -> ") or "") .. describe(msg.data))
            end
        end
    elseif opcode == 2 then -- Discord closed the connection, usually with a reason (4000 = bad app id)
        local data = json.decode(payload)
        local code = type(data) == "table" and data.code
        disconnect("DC-CLOSED" .. (code and ("-" .. tostring(code)) or ""), describe(data))
    elseif opcode == 3 then -- PING: Discord drops clients that don't answer
        local sent, err = conn:sendFrame(4, payload)
        if not sent then disconnect("DC-IO", "pong: " .. tostring(err)) end
    end
end

--- drives both the reconnect backoff and the read loop, so it needs a real dt:
-- called with none, the retry timer never advances and a failed connect is
-- permanent. A read that throws drops back to disconnected rather than
-- propagating.
---@param dt number
function RPC.update(dt)
    dt = dt or 0

    if state == "disconnected" then
        retryTimer = retryTimer - dt
        if retryTimer <= 0 then
            tryConnect()
            retryTimer = 5 -- retry every 5s if Discord isn't reachable yet
        end
        return
    end

    -- the pipe opened but Discord never answered READY (or CLOSE) -- treat
    -- it the same as a failed connect rather than waiting forever
    if state == "handshaking" then
        handshakeTimer = handshakeTimer + dt
        if handshakeTimer >= HANDSHAKE_TIMEOUT then
            return disconnect("DC-HANDSHAKE", ("Discord accepted the connection but sent no READY within %ds")
                :format(HANDSHAKE_TIMEOUT), HANDSHAKE_RETRY_DELAY)
        end
    end

    if not conn then return end

    local ok, err = pcall(function()
        local open, why = conn:pump()
        if not open then return disconnect("DC-LOST", why) end
        while conn do
            local opcode, payload = conn:popFrame()
            if not opcode then break end
            handleFrame(opcode, payload)
        end
    end)

    if not ok then disconnect("DC-INTERNAL", err) end
end

--- a failed write means the connection is gone, not that the frame should
-- be retried on it
---@param payload string
---@return boolean sent
local function sendCommand(payload)
    if state ~= "connected" or not conn then return false end
    local sent, err = conn:sendFrame(1, payload)
    if not sent then disconnect("DC-LOST", err) end
    return sent
end

---@param activity table # details/state/timestamps/assets
---@return boolean # sent; false while the connection isn't up
function RPC.setActivity(activity)
    return sendCommand(json.encode({
        cmd = "SET_ACTIVITY",
        args = {
            pid = getCurrentPid(),
            activity = activity,
        },
        nonce = nextNonce(),
    }))
end

---@return boolean sent
function RPC.clearActivity()
    return sendCommand(json.encode({
        cmd = "SET_ACTIVITY",
        args = { pid = getCurrentPid() },
        nonce = nextNonce(),
    }))
end

---@return string # "disconnected" | "handshaking" | "connected"
function RPC.state()
    return state
end

---@return boolean # true only once Discord has answered READY
function RPC.isReady()
    return state == "connected"
end

---@return string|nil
function RPC.getLastError()
    return RPC.lastError
end

--- sends CLOSE and drops the connection, so the presence clears now rather than
-- when Discord notices the process is gone
function RPC.shutdown()
    if conn then
        conn:sendFrame(2, "{}") -- opcode 2 = CLOSE; a failure here doesn't matter, we're leaving
        conn:close()
        conn = nil
    end
    state = "disconnected"
end

return RPC
