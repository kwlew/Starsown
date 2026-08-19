local Audio = require "core.audio"

local Settings = {}

Settings.FILENAME = "settings.lua"

Settings.defaults = {
    windowMode = "windowed", -- "windowed" | "borderless" | "exclusive"
    vsync = 0,
    msaa = 4,
    volume = 0.8,      -- master, scales every channel via love.audio.setVolume
    musicVolume = 0.8, -- channel volume, see core/audio.lua
    sfxVolume = 0.8,   -- channel volume, see core/audio.lua
    res_x = 1280,
    res_y = 720,
    language = "en",   -- validated against available locale files by I18n
    theme = "default", -- validated against available themes by UI.Theme
    titleFont = "acme", -- validated against available fonts by GameTitle
    customCursor = true, -- draws the game's own cursor; off shows the OS pointer instead
    reducedMotion = false, -- dampens ambient animation (starfield, nebula, twinkle, splash, title)
    shareStats = true,
}


local VALID_WINDOW_MODES = { windowed = true, borderless = true, exclusive = true }


Settings.MSAA_LEVELS = { 0, 2, 4, 8, 16, }

local VALID_MSAA = {}
for _, samples in ipairs(Settings.MSAA_LEVELS) do VALID_MSAA[samples] = true end

local function serializeValue(v)
    local t = type(v)
    if t == "string" then
        return string.format("%q", v)
    elseif t == "number" or t == "boolean" then
        return tostring(v)
    end
    return "nil"
end

local function serialize(settings)
    -- stable key order so the file diffs cleanly between saves
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

-- defaults overlaid with valid saved values only; keys not in defaults, or
-- with a type mismatch, are ignored, so junk in the file can't reach the game
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

                -- migrate pre-windowMode files that stored `fullscreen = true`
                if data.windowMode == nil and data.fullscreen == true then
                    settings.windowMode = "borderless"
                end

                if not VALID_WINDOW_MODES[settings.windowMode] then
                    settings.windowMode = Settings.defaults.windowMode
                end

                -- an older build stored the selector's *index* here, not the
                -- sample count, so files in the wild can hold values like 6
                if not VALID_MSAA[settings.msaa] then
                    settings.msaa = Settings.defaults.msaa
                end

                if type(settings.language) ~= "string" or settings.language == "" then
                    settings.language = Settings.defaults.language
                end

                -- kept out of I18n/Theme's own validation: this file loads
                -- during love.conf, before the graphics module exists for UI to load against
                if type(settings.theme) ~= "string" or settings.theme == "" then
                    settings.theme = Settings.defaults.theme
                end
            end
        end
    end

    return settings
end

function Settings.save(settings)
    return love.filesystem.write(Settings.FILENAME, serialize(settings))
end

-- Applies resolution + window mode + vsync in one setMode call. Current flags
-- are fetched and carried over because a bare setMode(w, h) RESETS every
-- unspecified flag (would silently drop msaa/resizable/highdpi). Skips the
-- call when nothing changed, since setMode recreates the window (visible flicker).
function Settings.applyGraphics(settings)
    local w, h, flags = love.window.getMode()

    local fullscreen = settings.windowMode ~= "windowed"
    local fullscreenType = (settings.windowMode == "exclusive") and "exclusive" or "desktop"

    local changed = flags.fullscreen ~= fullscreen
        or (fullscreen and flags.fullscreentype ~= fullscreenType)
        or flags.vsync ~= settings.vsync
        or flags.msaa ~= settings.msaa
        -- borderless fullscreen reports the desktop size via getMode, so the
        -- stored resolution only matters outside of it
        or (settings.windowMode ~= "borderless" and (w ~= settings.res_x or h ~= settings.res_y))
    if not changed then return end

    flags.fullscreen = fullscreen
    flags.fullscreentype = fullscreenType
    flags.vsync = settings.vsync
    flags.msaa = settings.msaa

    -- carrying over x/y captured while fullscreen (0,0) would park the title
    -- bar off-screen; nil coordinates center the window on the display
    if not fullscreen then
        flags.x, flags.y = nil, nil
    end

    love.window.setMode(settings.res_x, settings.res_y, flags)

    -- a driver can grant fewer samples than asked (16x often caps to 8x/4x);
    -- store what we actually got or the changed-check above never settles
    local w, h, granted = love.window.getMode()
    settings.msaa = granted.msaa or settings.msaa

    -- love.resize doesn't reliably fire on a programmatic setMode on this
    -- LÖVE build, so it's triggered by hand with the size we actually got
    if love.resize then love.resize(w, h) end

    -- setMode recreates the window, which on some Windows drivers resets
    -- cursor visibility to shown -- reassert whichever one the player
    -- actually wants rather than hardcoding hidden
    love.mouse.setVisible(not settings.customCursor)
end

function Settings.apply(settings)
    Settings.applyGraphics(settings)
    love.audio.setVolume(settings.volume)
    Audio.setVolume("music", settings.musicVolume)
    Audio.setVolume("sfx", settings.sfxVolume)
end

return Settings
