local Audio = require "core.audio"
local DisplayLimits = require "core.displayLimits"
local LuaSerialize = require "utils.luaSerialize"

local Settings = {}
local previews = setmetatable({}, { __mode = "k" })
local applyingGraphics = false
local GRAPHICS_KEYS = { "res_x", "res_y", "display", "windowMode", "vsync", "msaa" }

function Settings.graphicsSnapshot(settings)
    local snapshot = {}
    for _, key in ipairs(GRAPHICS_KEYS) do snapshot[key] = settings[key] end
    return snapshot
end

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
    display = 1,
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
        lines[#lines + 1] = string.format("    %s = %s,", key, LuaSerialize.serializeValue(value))
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

                -- a display index a monitor was unplugged out from under
                -- (or that never existed -- a save copied to another
                -- machine) falls back to the first display, same as a
                -- resolution the monitor lost falls back in options.lua.
                -- Safe to call before a window exists.
                if type(settings.display) ~= "number" or settings.display < 1
                    or (love.window and settings.display > love.window.getDisplayCount()) then
                    settings.display = Settings.defaults.display
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
    local safe = settings
    if previews[settings] then
        safe = {}
        for key, value in pairs(settings) do safe[key] = value end
        for key, value in pairs(previews[settings]) do safe[key] = value end
    end
    return love.filesystem.write(Settings.FILENAME, serialize(safe))
end

-- All save paths (including resize callbacks) retain the last confirmed graphics
-- until Keep. Immediate audio/interface changes can still be persisted safely.
function Settings.beginGraphicsPreview(settings)
    if previews[settings] then return true end
    local ok, err = Settings.save(settings)
    if not ok then return false, err end
    previews[settings] = Settings.graphicsSnapshot(settings)
    return true
end

function Settings.endGraphicsPreview(settings, keep)
    local baseline = previews[settings]
    previews[settings] = nil
    if keep then
        local ok, err = Settings.save(settings)
        if not ok then previews[settings] = baseline; return false, err end
    elseif baseline then
        for _, key in ipairs(GRAPHICS_KEYS) do
            if baseline[key] ~= settings[key] then previews[settings] = baseline; break end
        end
    end
    return true
end

function Settings.readGraphics(settings)
    local actualW, actualH, actual = love.window.getMode()
    settings.res_x, settings.res_y = actualW, actualH
    settings.display = actual.display or settings.display
    settings.msaa = actual.msaa or 0
    settings.vsync = actual.vsync or 0
    settings.windowMode = not actual.fullscreen and "windowed"
        or (actual.fullscreentype == "exclusive" and "exclusive" or "borderless")
    return actualW, actualH
end

--- applies resolution/mode/vsync/MSAA/display, and no-ops when nothing
-- actually changed so a stray Apply doesn't flicker the window. Writes back
-- the MSAA the driver actually granted, manually re-fires love.resize (this
-- LÖVE build doesn't reliably call it on a programmatic mode change), and
-- re-asserts cursor visibility, which some Windows drivers reset on every
-- setMode. Moving an exclusive-fullscreen window to a different display is a
-- known rough edge across platforms in LÖVE/SDL -- if it ever leaves the
-- window somewhere unreadable, the revert-countdown dialog in options.lua is
-- what rescues the player, same as it does for a bad resolution.
---@param settings table
function Settings.applyGraphics(settings)
    if settings.display < 1 or settings.display > love.window.getDisplayCount() then
        return false, "Display is no longer available"
    end
    local requested = Settings.graphicsSnapshot(settings)
    local w, h, current = love.window.getMode()
    local flags = {}
    for key, value in pairs(current) do flags[key] = value end
    local minW, minH = DisplayLimits.minimum(settings.display)
    local desiredW, desiredH = settings.res_x, settings.res_y
    if settings.windowMode == "windowed" then
        desiredW, desiredH = DisplayLimits.windowSize(desiredW, desiredH, settings.display)
    end
    local fullscreen = settings.windowMode ~= "windowed"
    local fullscreenType = settings.windowMode == "exclusive" and "exclusive" or "desktop"
    local changed = flags.minwidth ~= minW or flags.minheight ~= minH
        or flags.fullscreen ~= fullscreen
        or (fullscreen and flags.fullscreentype ~= fullscreenType)
        or flags.vsync ~= settings.vsync or flags.msaa ~= settings.msaa
        or flags.display ~= settings.display
        or (settings.windowMode ~= "borderless" and (w ~= desiredW or h ~= desiredH))
    flags.fullscreen, flags.fullscreentype = fullscreen, fullscreenType
    flags.vsync, flags.msaa, flags.display = settings.vsync, settings.msaa, settings.display
    flags.minwidth, flags.minheight = minW, minH
    if not fullscreen then flags.x, flags.y = nil, nil end

    if changed then
        applyingGraphics = true
        local called, ok, err = pcall(love.window.setMode, desiredW, desiredH, flags)
        applyingGraphics = false
        if not called or not ok then return false, called and err or ok end
    end
    local actualW, actualH = Settings.readGraphics(settings)
    local adjusted = false
    for _, key in ipairs(GRAPHICS_KEYS) do
        if not (requested.windowMode == "borderless" and (key == "res_x" or key == "res_y"))
            and requested[key] ~= settings[key] then adjusted = true end
    end
    if changed and love.resize then love.resize(actualW, actualH) end
    love.mouse.setVisible(not settings.customCursor)
    return true, nil, adjusted
end

--- called from main.lua's love.resize on every resize, not just a drag: a
-- live border-drag in windowed mode updates and persists the new size
-- directly, since unlike a mode change from Options this is always visibly
-- reversible by the player themselves (they're the one dragging it) and
-- doesn't need that flow's Apply/Keep/Revert safety net. A no-op whenever
-- res_x/res_y already match -- which is exactly the case right after
-- Settings.applyGraphics's own manual love.resize re-fire, so an Options
-- Apply never double-writes here ahead of the player confirming Keep.
-- Writes on every resize event during an active drag rather than debouncing:
-- this file is small and the write is rare and short-lived, so the
-- simplicity is worth more than the saved I/O.
---@param settings table
---@param w number
---@param h number
function Settings.trackWindowResize(settings, w, h)
    if applyingGraphics then return end
    if settings.windowMode ~= "windowed" then return end
    if settings.res_x == w and settings.res_y == h then return end
    settings.res_x, settings.res_y = w, h
    Settings.save(settings)
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
