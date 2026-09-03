local Audio = require "core.audio"

local Settings = {}

Settings.FILENAME = "settings.lua"

Settings.defaults = {
    windowMode = "windowed",
    vsync = 0,
    uncapFps = false,
    msaa = 4,
    volume = 0.8,
    musicVolume = 0.8,
    sfxVolume = 0.8,
    res_x = 1280,
    res_y = 720,
    language = "en",
    theme = "default",
    titleFont = "acme",
    customCursor = true,
    reducedMotion = false,
    showNebula = true,
    shareStats = false,
    statsConsentAsked = false,
}


local VALID_WINDOW_MODES = { windowed = true, borderless = true, exclusive = true }


Settings.MSAA_LEVELS = { 0, 2, 4, 8, 16, }

local VALID_MSAA = {}
for _, samples in ipairs(Settings.MSAA_LEVELS) do VALID_MSAA[samples] = true end

--- anything that isn't a string, number or boolean serializes to nil rather
-- than writing an unloadable file
---@param v any
---@return string
local function serializeValue(v)
    local t = type(v)
    if t == "string" then
        return string.format("%q", v)
    elseif t == "number" or t == "boolean" then
        return tostring(v)
    end
    return "nil"
end

--- a loadable Lua chunk, keys sorted so the saved file diffs cleanly. Only
-- keys in defaults are written; a missing one falls back to its default.
---@param settings table
---@return string
local function serialize(settings)
    local keys = {}
    for key in pairs(Settings.defaults) do keys[#keys + 1] = key end
    table.sort(keys)

    local lines = { "-- Saved settings. Delete this file to reset to defaults.", "return {" }
    for _, key in ipairs(keys) do
        local value = settings[key]
        if value == nil then value = Settings.defaults[key] end
        lines[#lines + 1] = string.format("    %s = %s,", key, serializeValue(value))
    end
    lines[#lines + 1] = "}"
    lines[#lines + 1] = ""
    return table.concat(lines, "\n")
end

--- defaults overlaid with the saved file, accepting a saved key only when it
-- exists in defaults and the type matches -- so a corrupt or hand-edited file
-- can't propagate into the game. Also carries the old-format migrations
-- (boolean fullscreen -> windowMode, and an MSAA selector index saved as if
-- it were a sample count).
---@return table settings
function Settings.load()
    local settings = {}
    for key, value in pairs(Settings.defaults) do
        settings[key] = value
    end

    if love.filesystem.getInfo(Settings.FILENAME) then
        local chunk = love.filesystem.load(Settings.FILENAME)
        if chunk then
            local ok, data = pcall(chunk)
            if ok and type(data) == "table" then
                for key, default in pairs(Settings.defaults) do
                    local value = data[key]
                    if value ~= nil and type(value) == type(default) then
                        settings[key] = value
                    end
                end

                if data.windowMode == nil and data.fullscreen == true then
                    settings.windowMode = "borderless"
                end

                if not VALID_WINDOW_MODES[settings.windowMode] then
                    settings.windowMode = Settings.defaults.windowMode
                end

                if not VALID_MSAA[settings.msaa] then
                    settings.msaa = Settings.defaults.msaa
                end

                if type(settings.language) ~= "string" or settings.language == "" then
                    settings.language = Settings.defaults.language
                end

                if type(settings.theme) ~= "string" or settings.theme == "" then
                    settings.theme = Settings.defaults.theme
                end
            end
        end
    end

    return settings
end

---@param settings table
---@return boolean success
---@return string? err
function Settings.save(settings)
    return love.filesystem.write(Settings.FILENAME, serialize(settings))
end

--- applies resolution/mode/vsync/MSAA, and no-ops when nothing actually
-- changed so a stray Apply doesn't flicker the window. Writes back the MSAA
-- the driver actually granted, manually re-fires love.resize (this LÖVE build
-- doesn't reliably call it on a programmatic mode change), and re-asserts
-- cursor visibility, which some Windows drivers reset on every setMode.
---@param settings table
function Settings.applyGraphics(settings)
    local w, h, flags = love.window.getMode()

    local fullscreen = settings.windowMode ~= "windowed"
    local fullscreenType = (settings.windowMode == "exclusive") and "exclusive" or "desktop"

    local changed = flags.fullscreen ~= fullscreen
        or (fullscreen and flags.fullscreentype ~= fullscreenType)
        or flags.vsync ~= settings.vsync
        or flags.msaa ~= settings.msaa
        or (settings.windowMode ~= "borderless" and (w ~= settings.res_x or h ~= settings.res_y))
    if not changed then return end

    flags.fullscreen = fullscreen
    flags.fullscreentype = fullscreenType
    flags.vsync = settings.vsync
    flags.msaa = settings.msaa

    if not fullscreen then
        flags.x, flags.y = nil, nil
    end

    love.window.setMode(settings.res_x, settings.res_y, flags)

    ---@diagnostic disable-next-line: redefined-local
    local w, h, granted = love.window.getMode()
    settings.msaa = granted.msaa or settings.msaa

    if love.resize then love.resize(w, h) end

    love.mouse.setVisible(not settings.customCursor)
end

--- graphics plus the three volume levels; the full boot-time apply
---@param settings table
function Settings.apply(settings)
    Settings.applyGraphics(settings)
    love.audio.setVolume(settings.volume)
    Audio.setVolume("music", settings.musicVolume)
    Audio.setVolume("sfx", settings.sfxVolume)
end

return Settings
