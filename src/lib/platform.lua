local function detectOS()
    if love and love.system then
        local name = love.system.getOS()
        if name == "OS X" then return "macos" end
        return name:lower()
    end

    if jit and jit.os then
        local map = { Windows = "windows", OSX = "macos", Linux = "linux" }
        return map[jit.os] or jit.os:lower()
    end

    if package.config:sub(1, 1) == "\\" then
        return "windows"
    end
    return "unix"
end

local osName = detectOS()

local Platform = {
    name      = osName,
    isWindows = osName == "windows",
    isMac     = osName == "macos",
    isLinux   = osName == "linux",
    isMobile  = osName == "android" or osName == "ios",
}

return Platform