local Platform = require("lib.platform")
local ffi = require("ffi")

local Pipe = {}
Pipe.__index = Pipe
local getCurrentPid

if Platform.isWindows then
    
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
    local GENERIC_READ = 0x80000000
    local GENERIC_WRITE = 0x40000000
    local OPEN_EXISTING = 3

    getCurrentPid = function() return tonumber(kernel32.GetCurrentProcessId()) end
        
    local function toWideString(s)
        local buf = ffi.new("WCHAR[?]", #s + 1)
        for i = 1, #s do buf[i-1] = s:byte(i) end
        buf[#s] = 0
        return buf
    end

    function Pipe.connect()
        for i = 0, 9 do
            local path = "\\\\.\\pipe\\discord-ipc-" .. i
            local handle = kernel32.CreateFileW(toWideString(path), bit.bor(GENERIC_READ, GENERIC_WRITE), 0, nil, OPEN_EXISTING, 0, nil)
            if handle ~= INVALID_HANDLE_VALUE then
                return setmetatable({
                    handle = handle
                }, Pipe)
            end
        end
        return nil
    end

    local function lastError(call)
        return ("%s failed (Windows error %d)"):format(call, tonumber(kernel32.GetLastError()))
    end

    function Pipe:write(data)
        local written = ffi.new("DWORD[1]")
        if kernel32.WriteFile(self.handle, data, #data, written, nil) == 0 then return false, lastError("WriteFile") end
        return true
    end

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

    function Pipe:close()
        kernel32.CloseHandle(self.handle)
    end

elseif Platform.isLinux or Platform.isMac then

    ffi.cdef(Platform.isMac
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
    local O_NONBLOCK  = Platform.isMac and 0x0004 or 0x800
    local EAGAIN      = Platform.isMac and 35 or 11
    local SUN_PATH_MAX = Platform.isMac and 104 or 108
    local MSG_NOSIGNAL = Platform.isMac and 0 or 0x4000
    local SOL_SOCKET, SO_NOSIGPIPE = 0xffff, 0x1022

    local function lastError(call)
        local errno = ffi.errno()
        return ("%s failed: %s (errno %d)"):format(call, ffi.string(C.strerror(errno)), errno)
    end

    getCurrentPid = function() return tonumber(C.getpid()) end

    local SANDBOXES = { "", "/app/com.discordapp.Discord", "/app/com.discordapp.DiscordCanary", "/snap.discord" }

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
                    if Platform.isMac then addr.sun_len = ffi.sizeof(addr) end
                    ---@diagnostic disable-next-line: undefined-field
                    ffi.copy(addr.sun_path, path)
                    if C.connect(fd, addr, ffi.sizeof(addr)) == 0 then
                        local flags = C.fcntl(fd, F_GETFL, 0)
                        C.fcntl(fd, F_SETFL, bit.bor(flags, O_NONBLOCK))
                        if Platform.isMac then
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

    function Pipe:write(data)
        local sent = 0
        while sent < #data do
            local n = C.send(self.fd, ffi.cast("const char*", data) + sent, #data - sent, MSG_NOSIGNAL)
            if n < 0 then return false, lastError("send") end
            sent = sent + tonumber(n)
        end
        return true
    end

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

    function Pipe:close()
        C.close(self.fd)
    end

else
    error("discordrpc.lua: unsupported platform")
end

Pipe.getCurrentPid = getCurrentPid

return Pipe