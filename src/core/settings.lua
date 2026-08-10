-- src/core/settings.lua
-- Loads and saves player settings to the LÖVE save directory (keyed by the
-- `identity` set in conf.lua). The on-disk format is a plain Lua table so it
-- can be read back with love.filesystem.load; loading is defensive so a
-- missing, corrupt, or hand-edited file always falls back to defaults.

local Audio = require "core.audio"

local Settings = {}

Settings.FILENAME = "settings.lua"

Settings.defaults = {
    windowMode = "windowed", -- "windowed" | "borderless" | "exclusive"
    vsync = 0,
    msaa = 4,          -- multisample antialiasing samples (smooths circles/rounded corners)
    volume = 0.8,      -- master: applied via love.audio.setVolume, scales every channel
    musicVolume = 0.8, -- channel volume, see src/core/audio.lua
    sfxVolume = 0.8,   -- channel volume, see src/core/audio.lua
    res_x = 1280,
    res_y = 720,
    language = "en", -- locale code; validated against available files by I18n
    theme = "default", -- UI theme name; validated against available themes by UI.Theme
    shareStats = true,
}

-- Allowed values for string settings; anything else in the file falls back
-- to the default (a bare type check isn't enough for enums).
local VALID_WINDOW_MODES = { windowed = true, borderless = true, exclusive = true }

-- Multisample counts the game offers, in ascending order. Lives here rather
-- than in the Options screen because conf.lua feeds settings.msaa straight into
-- window creation at boot, long before any UI exists: a value off this list can
-- produce a broken framebuffer (a 6 here renders the whole window white), and
-- then there is no way for the player to reach Options and correct it. Load
-- must be the thing that guarantees a usable value.
--
-- No 1: LÖVE treats 0 and 1 alike, so it would duplicate "off".
Settings.MSAA_LEVELS = { 0, 2, 4, 8, 16 }

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
    -- Stable key order so the file diffs cleanly between saves.
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

-- Returns a fresh settings table: defaults overlaid with any valid saved
-- values. Only keys present in defaults are accepted, and only when the saved
-- value's type matches, so junk in the file can never propagate into the game.
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

                -- Migrate pre-windowMode files that stored `fullscreen = true`.
                if data.windowMode == nil and data.fullscreen == true then
                    settings.windowMode = "borderless"
                end

                if not VALID_WINDOW_MODES[settings.windowMode] then
                    settings.windowMode = Settings.defaults.windowMode
                end

                -- An older build wrote the selector's *index* here rather than
                -- the sample count, so files in the wild hold values like 6.
                if not VALID_MSAA[settings.msaa] then
                    settings.msaa = Settings.defaults.msaa
                end

                -- Language is validated for shape only here; I18n does the
                -- authoritative check against the locale files it discovered
                -- (unknown codes fall back to English at setLanguage time).
                if type(settings.language) ~= "string" or settings.language == "" then
                    settings.language = Settings.defaults.language
                end

                -- Theme, likewise: UI.Theme owns the list of palettes it ships
                -- and falls back to the default at setTheme time. Keeping that
                -- knowledge out of here is what lets conf.lua require this file
                -- during love.conf, before there is any graphics module for the
                -- UI package to be loaded against.
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

-- Applies resolution + window mode + vsync in one setMode call. The current
-- window flags are fetched and carried over because a bare setMode(w, h)
-- RESETS every unspecified flag — it would silently drop msaa, resizable,
-- and highdpi from conf.lua. Skips the call entirely when nothing changed,
-- since setMode recreates the window (visible flicker).
--
-- Window modes: "windowed" (no fullscreen), "borderless" (desktop-type
-- fullscreen at desktop resolution), "exclusive" (real fullscreen at
-- res_x x res_y — can change the display mode). The cursor is re-shown after
-- every mode change: exclusive fullscreen in particular can hide the OS
-- cursor on some Windows drivers.
function Settings.applyGraphics(settings)
    local w, h, flags = love.window.getMode()

    local fullscreen = settings.windowMode ~= "windowed"
    local fullscreenType = (settings.windowMode == "exclusive") and "exclusive" or "desktop"

    local changed = flags.fullscreen ~= fullscreen
        or (fullscreen and flags.fullscreentype ~= fullscreenType)
        or flags.vsync ~= settings.vsync
        or flags.msaa ~= settings.msaa
        -- In borderless fullscreen, getMode reports the desktop size, so the
        -- stored resolution only matters (and is only compared) outside it.
        or (settings.windowMode ~= "borderless" and (w ~= settings.res_x or h ~= settings.res_y))
    if not changed then return end

    flags.fullscreen = fullscreen
    flags.fullscreentype = fullscreenType
    flags.vsync = settings.vsync
    flags.msaa = settings.msaa

    -- Center the window whenever the target is windowed: carrying over the
    -- x/y captured while fullscreen (0,0) would park the title bar off the
    -- top of the screen. With nil coordinates, setMode centers on the display.
    if not fullscreen then
        flags.x, flags.y = nil, nil
    end

    love.window.setMode(settings.res_x, settings.res_y, flags)

    -- A driver can grant fewer samples than were asked for (16x is commonly
    -- capped to 8x or 4x). Store what we actually got: otherwise the comparison
    -- above never settles, so every later call recreates the window, and the
    -- request rather than the reality is what gets written to the save file.
    local _, _, granted = love.window.getMode()
    settings.msaa = granted.msaa or settings.msaa

    love.mouse.setVisible(true)
end

-- Pushes the settings into LÖVE (call once at boot and whenever they change).
-- Master multiplies every channel via love.audio.setVolume; music/sfx are
-- per-channel volumes applied through src/core/audio.lua (see there for why).
function Settings.apply(settings)
    Settings.applyGraphics(settings)
    love.audio.setVolume(settings.volume)
    Audio.setVolume("music", settings.musicVolume)
    Audio.setVolume("sfx", settings.sfxVolume)
end

return Settings
