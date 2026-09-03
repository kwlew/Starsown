---@diagnostic disable: duplicate-set-field, inject-field
--- Runs before the window exists, which is why it reads the saved settings
-- itself rather than waiting for love.load: resolution, display mode, vsync and
-- MSAA have to be right at creation. Reading them needs the save directory, so
-- the identity is set first. A failed or missing settings file leaves the
-- defaults above in place.
---@param t table # LÖVE's config table
function love.conf(t)
    t.identity = "TD-Idle"
    t.version = "11.5"
    t.console = false

    t.window.title = "Starsown"
    t.window.icon = "assets/icon/starsown-128.png"
    t.window.width = 1280
    t.window.height = 720
    t.window.resizable = false
    t.window.vsync = 0
    t.window.msaa = 4
    t.window.fullscreen = false
    t.window.highdpi = true

    local ok, settings = pcall(function()
        love.filesystem.setIdentity(t.identity)
        return require("core.settings").load()
    end)
    if ok and settings then
        t.window.vsync = settings.vsync
        t.window.msaa = settings.msaa
        if settings.windowMode == "borderless" then
            t.window.fullscreen = true
            t.window.fullscreentype = "desktop"
        elseif settings.windowMode == "exclusive" then
            t.window.fullscreen = true
            t.window.fullscreentype = "exclusive"
            t.window.width = settings.res_x
            t.window.height = settings.res_y
        else
            t.window.width = settings.res_x
            t.window.height = settings.res_y
        end
    end

    t.modules.joystick = false
    t.modules.physics = false
end
