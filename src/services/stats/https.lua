--- Finds lua-https, which LÖVE can't load from the game.

local Https = {}

-- copies the build scripts package into the .love
local BUNDLED = { Linux = "native/linux-x64/https.so" }

--- the dev copy tools/ keeps beside an unpackaged src/
---@return string|nil
local function devPath()
    if love.filesystem.isFused() then return nil end
    local source = love.filesystem.getSource()
    local ext = love.system.getOS() == "Windows" and "dll" or "so"
    local file = io.open(source .. "/../.tools/lua-https/https." .. ext, "rb")
    if not file then return nil end
    file:close()
    return source .. "/../.tools/lua-https/?." .. ext
end

--- extracts the bundled copy, one folder per content hash
---@return string|nil
local function bundledPath()
    local path = BUNDLED[love.system.getOS()]
    if not path or jit.arch ~= "x64" then return nil end
    local bytes = love.filesystem.read(path)
    if not bytes then return nil end

    local dir = "native/" .. love.data.encode("string", "hex", love.data.hash("md5", bytes))
    if not love.filesystem.getInfo(dir .. "/https.so", "file") then
        love.filesystem.createDirectory(dir)
        local ok, err = love.filesystem.write(dir .. "/https.so", bytes)
        if not ok then
            print("[stats] couldn't extract the bundled lua-https: " .. tostring(err))
            return nil
        end
    end
    return love.filesystem.getSaveDirectory() .. "/" .. dir .. "/?.so"
end

---@return string|nil # a package.cpath entry
function Https.cpath()
    return devPath() or bundledPath()
end

--- loads lua-https here, as the worker would; for --check-https
---@return boolean ok
---@return string|nil err
function Https.check()
    local cpath = Https.cpath()
    if cpath then package.cpath = cpath .. ";" .. package.cpath end
    local ok, err = pcall(require, "https")
    return ok, not ok and tostring(err) or nil
end

return Https
