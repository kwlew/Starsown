-- conf.lua
function love.conf(t)
    t.identity = "TD-Idle"          -- save-directory name (love.filesystem writes here)
    t.version = "11.5"
    t.console = false

    t.window.title = "TD Idle"
    t.window.icon = "assets/icon.png"
    t.window.width = 1280
    t.window.height = 720
    t.window.resizable = false
    t.window.vsync = 0            -- 0 = off, 1 = on, -1 = adaptive
    t.window.msaa = 4     -- multisample antialiasing samples (smooths circles/rounded corners)
    t.window.fullscreen = false
    t.window.highdpi = true         -- retina/hidpi support

    -- Create the window with the SAVED graphics settings, not the defaults
    -- above: applying them later (loading state) would call setMode, which
    -- recreates the window — a visible resize right after launch, plus a
    -- frame stall that fast-forwards the loading screen. love.filesystem is
    -- functional during love.conf (conf.lua itself is loaded through it),
    -- but the save-dir identity isn't set until after conf returns, so set
    -- it manually before reading. pcall: if anything fails (e.g. different
    -- cwd so lib/ doesn't resolve), the defaults above still stand.
    local ok, settings = pcall(function()
        love.filesystem.setIdentity(t.identity)
        return require("lib.settings").load()
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