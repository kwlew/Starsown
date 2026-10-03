--- Reading and writing settings.lua, validated against the defaults.

local Defaults = require("core.settings.defaults")
local LuaSerialize = require("utils.luaSerialize")

local Store = {}

Store.FILENAME = "settings.lua"

---@param list any[]
---@return table<any, boolean>
local function setOf(list)
    local set = {}
    for _, value in ipairs(list) do set[value] = true end
    return set
end

local VALID_WINDOW_MODES = setOf(Defaults.WINDOW_MODES)
local VALID_MSAA = setOf(Defaults.MSAA_LEVELS)

---@return table
local function fresh()
    local settings = {}
    for key, value in pairs(Defaults.values) do settings[key] = value end
    return settings
end

---@return table|nil
local function readFile()
    if not love.filesystem.getInfo(Store.FILENAME) then return nil end
    local chunk = love.filesystem.load(Store.FILENAME)
    if not chunk then return nil end
    local ok, data = pcall(chunk)
    return ok and type(data) == "table" and data or nil
end

--- keeps only known keys whose type matches the default
---@param settings table
---@param data table
local function merge(settings, data)
    for key, default in pairs(Defaults.values) do
        local value = data[key]
        if value ~= nil and type(value) == type(default) then settings[key] = value end
    end
    if data.windowMode == nil and data.fullscreen == true then -- old saves
        settings.windowMode = "borderless"
    end
end

---@param settings table
local function validate(settings)
    local d = Defaults.values
    if not VALID_WINDOW_MODES[settings.windowMode] then settings.windowMode = d.windowMode end
    if not VALID_MSAA[settings.msaa] then settings.msaa = d.msaa end
    if settings.display < 1 or (love.window and settings.display > love.window.getDisplayCount()) then
        settings.display = d.display
    end
    if settings.language == "" then settings.language = d.language end
    if settings.theme == "" then settings.theme = d.theme end
end

--- defaults overlaid with the saved file
---@return table
function Store.read()
    local settings = fresh()
    local data = readFile()
    if data then
        merge(settings, data)
        validate(settings)
    end
    return settings
end

---@param settings table
---@return string
local function serialize(settings)
    local keys = {}
    for key in pairs(Defaults.values) do keys[#keys + 1] = key end
    table.sort(keys)

    local lines = { "-- Saved settings. Delete this file to reset to defaults.", "return {" }
    for _, key in ipairs(keys) do
        local value = settings[key]
        if value == nil then value = Defaults.values[key] end
        lines[#lines + 1] = ("    %s = %s,"):format(key, LuaSerialize.value(value))
    end
    lines[#lines + 1] = "}"
    lines[#lines + 1] = ""
    return table.concat(lines, "\n")
end

---@param settings table
---@return boolean ok
---@return string? err
function Store.write(settings)
    return love.filesystem.write(Store.FILENAME, serialize(settings))
end

return Store
