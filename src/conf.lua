--- Window creation, from saved settings when they exist.

local Globals = require("globals")

---@diagnostic disable-next-line: duplicate-set-field
function love.conf(t)
    t.identity = Globals.game.name
    t.version = Globals.game.loveVersion
    t.console = false

    t.window.title = Globals.game.name
    t.window.icon = Globals.game.icon
    t.window.width = Globals.window.width
    t.window.height = Globals.window.height
    t.window.resizable = true
    t.window.vsync = 0
    t.window.msaa = 4
    t.window.fullscreen = false
    t.window.highdpi = true

    -- the save directory needs the identity before reading
    local ok, settings = pcall(function()
        love.filesystem.setIdentity(t.identity)
        return require("core.settings.store").read()
    end)
    if ok and settings then
        t.window.vsync = settings.vsync
        t.window.msaa = settings.msaa
        t.window.display = settings.display
        t.window.fullscreen = settings.windowMode ~= "windowed"
        t.window.fullscreentype = settings.windowMode == "exclusive" and "exclusive" or "desktop"
        if settings.windowMode ~= "borderless" then
            t.window.width, t.window.height = settings.res_x, settings.res_y
        end
    end

    local Limits = require("core.display.limits")
    local display = t.window.display or 1
    t.window.minwidth, t.window.minheight = Limits.minimum(display)
    if not t.window.fullscreen then
        t.window.width, t.window.height = Limits.windowSize(t.window.width, t.window.height, display)
    end

    t.modules.joystick = false
    t.modules.physics = false
end
