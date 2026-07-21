--[[
    discordrpc.lua
    ------------------------------------------------------------------
    A from-scratch Discord Rich Presence client for LÖVE2D.

    No external Discord libraries are used. This talks directly to
    Discord's local IPC transport:
      - Windows: a named pipe  \\.\pipe\discord-ipc-N
      - macOS/Linux: a Unix domain socket  $XDG_RUNTIME_DIR/discord-ipc-N
                     (falls back to $TMPDIR, $TMP, $TEMP, /tmp)

    It relies only on:
      - LuaJIT's built-in `ffi` and `bit` libraries (ship with LÖVE)
      - `love.system.getOS()` for platform detection (optional — falls
        back to `jit.os` if you ever run this outside LÖVE)

    Protocol notes (Discord IPC, informally documented, stable for years):
      Each message is a binary frame:
          [4 bytes opcode, little-endian][4 bytes length, little-endian][JSON payload]
      Opcodes:
          0 = HANDSHAKE   1 = FRAME   2 = CLOSE   3 = PING   4 = PONG

      Handshake: client sends opcode 0 with {"v":1,"client_id":"..."}.
      Discord responds with opcode 1 containing a DISPATCH/READY event.
      After that, opcode 1 frames carry commands like SET_ACTIVITY.

    USAGE (in your game):

        local RPC = require("discordrpc")

        function love.load()
            RPC.initialize("YOUR_DISCORD_APPLICATION_ID")
        end

        function love.update(dt)
            RPC.update(dt)
        end

        -- whenever your game state changes:
        RPC.setActivity({
            details = "Exploring the Rescue Maze",
            state = "In a match",
            timestamps = { start = os.time() },
            assets = {
                large_image = "game_logo",
                large_text = "My Awesome Game",
                small_image = "playing_icon",
                small_text = "Playing",
            },
        })

        function love.quit()
            RPC.shutdown()
        end

    CAVEATS (read before shipping):
      - This only implements local Rich Presence (details/state/images/
        timestamps/buttons). Join/Spectate/ask-to-join requires you to
        also handle ACTIVITY_JOIN / ACTIVITY_SPECTATE events and a
        running lobby system — not included here.
      - Requires LuaJIT (which LÖVE uses), NOT plain Lua/Lua 5.4 — `ffi`
        does not exist outside LuaJIT.
      - Discord must be running locally. If it's not, RPC.update() will
        just keep retrying quietly every few seconds — your game never
        blocks or crashes waiting for it.
      - pid is sent so Discord can clear the presence automatically if
        your game process dies without calling RPC.shutdown().
--]]

local ffi = require("ffi")

------------------------------------------------------------------
-- Platform detection
------------------------------------------------------------------

local isWindows, isMac, isLinux = false, false, false

if love and love.system then
    local osName = love.system.getOS()
    isWindows = (osName == "Windows")
    isMac     = (osName == "OS X")
    isLinux   = (osName == "Linux")
else
    -- Fallback if this is ever loaded outside LÖVE (e.g. a quick luajit test script)
    isWindows = (jit and jit.os == "Windows")
    isMac     = (jit and jit.os == "OSX")
    isLinux   = (jit and jit.os == "Linux")
end

------------------------------------------------------------------
-- Tiny JSON encoder/decoder (just enough for Discord's payloads —
-- no external JSON library dependency)
------------------------------------------------------------------

local json = {}

local function isArray(t)
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" then return false end
        n = n + 1
    end
    return n == #t
end

local escapeMap = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }

local function escapeStr(s)
    return (s:gsub('[%z\1-\31\\"]', function(c)
        return escapeMap[c] or string.format('\\u%04x', c:byte())
    end))
end

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

function json.decode(str)
    local pos = 1
    local parseValue

    local function skipWhitespace()
        local _, e = str:find("^%s*", pos)
        pos = e + 1
    end

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

    local function parseNumber()
        local s, e = str:find("^%-?%d+%.?%d*[eE]?[+%-]?%d*", pos)
        local numStr = str:sub(s, e)
        pos = e + 1
        return tonumber(numStr)
    end

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

------------------------------------------------------------------
-- Frame packing helpers (4-byte little-endian uint32 headers)
------------------------------------------------------------------

local function packU32LE(n)
    return string.char(
        n % 256,
        math.floor(n / 256) % 256,
        math.floor(n / 65536) % 256,
        math.floor(n / 16777216) % 256
    )
end

local function unpackU32LE(s, offset)
    local b1, b2, b3, b4 = s:byte(offset, offset + 3)
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

------------------------------------------------------------------
-- Pipe: platform-specific transport (Windows named pipe / Unix socket)
------------------------------------------------------------------

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
    ]]

    local bit = require("bit")
    local kernel32 = ffi.load("kernel32")
    local INVALID_HANDLE_VALUE = ffi.cast("HANDLE", -1)
    local GENERIC_READ  = 0x80000000
    local GENERIC_WRITE = 0x40000000
    local OPEN_EXISTING = 3

    getCurrentPid = function() return tonumber(kernel32.GetCurrentProcessId()) end

    local function toWideString(s)
        local buf = ffi.new("WCHAR[?]", #s + 1)
        for i = 1, #s do buf[i - 1] = s:byte(i) end
        buf[#s] = 0
        return buf
    end

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

    function Pipe:write(data)
        local written = ffi.new("DWORD[1]")
        local ok = kernel32.WriteFile(self.handle, data, #data, written, nil)
        return ok ~= 0
    end

    -- returns number of bytes currently sitting in the pipe, without blocking
    function Pipe:available()
        local totalAvail = ffi.new("DWORD[1]")
        local ok = kernel32.PeekNamedPipe(self.handle, nil, 0, nil, totalAvail, nil)
        if ok == 0 then return 0 end
        return tonumber(totalAvail[0])
    end

    function Pipe:read(n)
        local buf = ffi.new("char[?]", n)
        local readCount = ffi.new("DWORD[1]")
        local ok = kernel32.ReadFile(self.handle, buf, n, readCount, nil)
        if ok == 0 then return nil end
        return ffi.string(buf, tonumber(readCount[0]))
    end

    function Pipe:close()
        kernel32.CloseHandle(self.handle)
    end

elseif isLinux or isMac then

    ffi.cdef[[
        typedef unsigned short sa_family_t;
        struct sockaddr_un { sa_family_t sun_family; char sun_path[108]; };
        int socket(int domain, int type, int protocol);
        int connect(int sockfd, const struct sockaddr_un *addr, unsigned int addrlen);
        long read(int fd, void *buf, unsigned long count);
        long write(int fd, const void *buf, unsigned long count);
        int close(int fd);
        int fcntl(int fd, int cmd, int arg);
        int getpid(void);
    ]]

    local bit = require("bit")
    local C = ffi.C
    local AF_UNIX     = 1
    local SOCK_STREAM = 1
    local F_GETFL     = 3
    local F_SETFL     = 4
    -- O_NONBLOCK differs between Linux and Darwin (macOS) libc:
    local O_NONBLOCK  = isMac and 0x0004 or 0x800

    getCurrentPid = function() return tonumber(C.getpid()) end

    local function candidateDirs()
        local dirs = {}
        for _, name in ipairs({ "XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP" }) do
            local v = os.getenv(name)
            if v and v ~= "" then dirs[#dirs + 1] = v end
        end
        dirs[#dirs + 1] = "/tmp"
        return dirs
    end

    function Pipe.connect()
        for _, dir in ipairs(candidateDirs()) do
            for i = 0, 9 do
                local path = dir .. "/discord-ipc-" .. i
                local fd = C.socket(AF_UNIX, SOCK_STREAM, 0)
                if fd >= 0 then
                    local addr = ffi.new("struct sockaddr_un")
                    addr.sun_family = AF_UNIX
                    ffi.copy(addr.sun_path, path)
                    if C.connect(fd, addr, ffi.sizeof(addr)) == 0 then
                        local flags = C.fcntl(fd, F_GETFL, 0)
                        C.fcntl(fd, F_SETFL, bit.bor(flags, O_NONBLOCK))
                        return setmetatable({ fd = fd }, Pipe)
                    else
                        C.close(fd)
                    end
                end
            end
        end
        return nil
    end

    function Pipe:write(data)
        local n = C.write(self.fd, data, #data)
        return n == #data
    end

    -- Unix path: socket is already non-blocking, so we just attempt reads;
    -- there's no cheap "peek" equivalent, so the connection layer above
    -- calls read() in a loop until it comes back empty.
    function Pipe:available() return nil end

    function Pipe:read(n)
        local buf = ffi.new("char[?]", n)
        local result = C.read(self.fd, buf, n)
        if result <= 0 then return nil end
        return ffi.string(buf, result)
    end

    function Pipe:close()
        C.close(self.fd)
    end

else
    error("discordrpc.lua: unsupported platform")
end

------------------------------------------------------------------
-- Connection: buffers raw bytes into complete frames
------------------------------------------------------------------

local Connection = {}
Connection.__index = Connection

function Connection.new(pipe)
    return setmetatable({ pipe = pipe, buffer = "" }, Connection)
end

function Connection:pump()
    if self.pipe.available and self.pipe:available() ~= nil then
        -- Windows path: ask how many bytes are waiting, then read exactly that many
        local avail = self.pipe:available()
        if avail > 0 then
            local chunk = self.pipe:read(avail)
            if chunk then self.buffer = self.buffer .. chunk end
        end
    else
        -- Unix path: non-blocking socket, keep reading chunks until empty
        while true do
            local chunk = self.pipe:read(4096)
            if not chunk or #chunk == 0 then break end
            self.buffer = self.buffer .. chunk
            if #chunk < 4096 then break end
        end
    end
end

function Connection:popFrame()
    if #self.buffer < 8 then return nil end
    local opcode = unpackU32LE(self.buffer, 1)
    local length = unpackU32LE(self.buffer, 5)
    if #self.buffer < 8 + length then return nil end
    local payload = self.buffer:sub(9, 8 + length)
    self.buffer = self.buffer:sub(9 + length)
    return opcode, payload
end

function Connection:sendFrame(opcode, payloadStr)
    return self.pipe:write(packU32LE(opcode) .. packU32LE(#payloadStr) .. payloadStr)
end

function Connection:close()
    self.pipe:close()
end

------------------------------------------------------------------
-- Public API
------------------------------------------------------------------

local RPC = {
    connected = false,
    lastError = nil,
}

local clientId = nil
local conn = nil
local state = "disconnected" -- disconnected -> handshaking -> connected
local retryTimer = 0
local nonceCounter = 0

local function nextNonce()
    nonceCounter = nonceCounter + 1
    return tostring(os.time()) .. "-" .. nonceCounter
end

function RPC.initialize(discordApplicationId)
    clientId = discordApplicationId
    state = "disconnected"
    retryTimer = 0
end

local function tryConnect()
    local pipe = Pipe.connect()
    if pipe then
        conn = Connection.new(pipe)
        conn:sendFrame(0, json.encode({ v = 1, client_id = clientId }))
        state = "handshaking"
    end
end

local function handleFrame(opcode, payload)
    if opcode == 1 then
        local msg = json.decode(payload)
        if msg then
            if msg.evt == "READY" then
                state = "connected"
                RPC.connected = true
            elseif msg.evt == "ERROR" then
                RPC.lastError = msg.data and msg.data.message or "unknown error"
            end
        end
    elseif opcode == 2 then -- Discord closed the connection
        RPC.connected = false
        state = "disconnected"
        if conn then conn:close() end
        conn = nil
    end
end

-- Call this every frame from love.update(dt)
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

    if not conn then return end

    local ok, err = pcall(function()
        conn:pump()
        while true do
            local opcode, payload = conn:popFrame()
            if not opcode then break end
            handleFrame(opcode, payload)
        end
    end)

    if not ok then
        RPC.lastError = err
        RPC.connected = false
        state = "disconnected"
        conn = nil
    end
end

function RPC.setActivity(activity)
    if state ~= "connected" or not conn then return false end
    local payload = json.encode({
        cmd = "SET_ACTIVITY",
        args = {
            pid = getCurrentPid(),
            activity = activity,
        },
        nonce = nextNonce(),
    })
    return conn:sendFrame(1, payload)
end

function RPC.clearActivity()
    if state ~= "connected" or not conn then return false end
    local payload = json.encode({
        cmd = "SET_ACTIVITY",
        args = { pid = getCurrentPid() },
        nonce = nextNonce(),
    })
    return conn:sendFrame(1, payload)
end

function RPC.isReady()
    return state == "connected"
end

function RPC.getLastError()
    return RPC.lastError
end

function RPC.shutdown()
    if conn then
        conn:sendFrame(2, "") -- opcode 2 = CLOSE
        conn:close()
        conn = nil
    end
    state = "disconnected"
    RPC.connected = false
end

return RPC