function love.conf(t)
    t.identity = "TD-Idle"
    t.version = "11.5"
    t.console = false

    t.window.title = "TD Idle"
    t.window.icon = "assets/TD-Idle.png"
    t.window.width = 1280
    t.window.height = 720
    t.window.resizable = false
    t.window.vsync = 0
    t.window.msaa = 4
    t.window.fullscreen = false
    t.window.highdpi = true

    -- override the defaults above with whatever's saved
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
