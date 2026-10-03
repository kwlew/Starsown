--- Pushing graphics settings onto the window, and reading them back.

local Defaults = require("core.settings.defaults")
local Limits = require("core.display.limits")
local Saver = require("core.settings.saver")

local Window = {}

local applying = false
local applied = nil -- the mode we last set; getMode can't be trusted

--- what the window reports, which can lag a fullscreen switch
---@param flags table
---@param expected string # the mode we asked for
---@return string
local function reportedMode(flags, expected)
    if not flags.fullscreen then return "windowed" end
    -- LÖVE reports exclusive as "desktop", so trust the request
    return expected ~= "windowed" and expected or "borderless"
end

--- overwrites the graphics keys with what the window really has
---@param settings table
---@return number w
---@return number h
function Window.read(settings)
    local w, h, flags = love.window.getMode()
    settings.res_x, settings.res_y = w, h
    settings.display = flags.display or settings.display
    settings.msaa = flags.msaa or 0
    settings.vsync = flags.vsync or 0
    settings.windowMode = reportedMode(flags, settings.windowMode)
    return w, h
end

---@param settings table
---@return number w
---@return number h
---@return table flags
---@return boolean changed
local function plan(settings)
    local w, h, reported = love.window.getMode()
    local flags = {}
    for key, value in pairs(reported) do flags[key] = value end

    local minW, minH = Limits.minimum(settings.display)
    local desiredW, desiredH = settings.res_x, settings.res_y
    if settings.windowMode == "windowed" then
        desiredW, desiredH = Limits.windowSize(desiredW, desiredH, settings.display)
    end
    local fullscreen = settings.windowMode ~= "windowed"
    local fullscreenType = settings.windowMode == "exclusive" and "exclusive" or "desktop"

    -- the mode we applied, not getMode's: that lags on Wayland
    local current = applied or reportedMode(reported, settings.windowMode)
    local changed = flags.minwidth ~= minW or flags.minheight ~= minH
        or current ~= settings.windowMode
        or flags.vsync ~= settings.vsync or flags.msaa ~= settings.msaa
        or flags.display ~= settings.display
        or (settings.windowMode ~= "borderless" and (w ~= desiredW or h ~= desiredH))

    flags.fullscreen, flags.fullscreentype = fullscreen, fullscreenType
    flags.vsync, flags.msaa, flags.display = settings.vsync, settings.msaa, settings.display
    flags.minwidth, flags.minheight = minW, minH
    if not fullscreen then flags.x, flags.y = nil, nil end
    return desiredW, desiredH, flags, changed
end

--- applies mode/size/vsync/MSAA/display; no-op when nothing changed
---@param settings table
---@return boolean ok
---@return string|nil err
---@return boolean|nil adjusted # the driver granted something else
---@return boolean|nil changed # setMode ran, recreating the GL context
function Window.apply(settings)
    if settings.display < 1 or settings.display > love.window.getDisplayCount() then
        return false, "Display is no longer available"
    end
    local requested = Saver.snapshot(settings)
    local w, h, flags, changed = plan(settings)

    if changed then
        applying = true
        local called, result, err = pcall(love.window.setMode, w, h, flags)
        applying = false
        local failure
        if not called then
            failure = tostring(result) -- setMode threw; result is the error
        elseif not result then
            failure = err or "setMode failed"
        end
        if failure then
            applied = nil -- unknown now; ask the window next time
            return false, failure
        end
    end
    applied = requested.windowMode

    local actualW, actualH = Window.read(settings)
    settings.windowMode = requested.windowMode -- setMode succeeded, so it's this
    local adjusted = false
    for _, key in ipairs(Defaults.GRAPHICS_KEYS) do
        local sizeKey = key == "res_x" or key == "res_y"
        if not (requested.windowMode == "borderless" and sizeKey) and requested[key] ~= settings[key] then
            adjusted = true
        end
    end

    -- LÖVE doesn't reliably fire resize on a programmatic change
    if changed and love.resize then love.resize(actualW, actualH) end
    love.mouse.setVisible(not settings.customCursor) -- some drivers reset it
    return true, nil, adjusted, changed
end

--- persists a player's live window drag
---@param settings table
---@param w number
---@param h number
function Window.trackResize(settings, w, h)
    if applying or settings.windowMode ~= "windowed" then return end
    if settings.res_x == w and settings.res_y == h then return end
    settings.res_x, settings.res_y = w, h
    Saver.save(settings)
end

return Window
