-- conf.lua
function love.conf(t)
    t.identity = "TD-Idle"          -- save-directory name (love.filesystem writes here)
    t.version = "12.0"
    t.console = false

    -- Top-level in 12.0. This was t.window.highdpi through 11.x, and that field
    -- is now ignored with a deprecation warning — setting it here, not under
    -- t.window, is what actually enables per-monitor DPI scaling.
    t.highdpi = true                -- retina/hidpi support

    -- 12.0 added a Vulkan backend and prefers it on Windows; 11.x was OpenGL
    -- only. Vulkan is fine on an empty frame and through 4x MSAA, but at 8x it
    -- falls off a fast path and the cost of drawing the menu goes up ~5x.
    -- Measured on an RTX 3050 laptop at 1600x900, marginal cost of one full
    -- menu scene:
    --
    --            msaa 0     msaa 4     msaa 8
    --   Vulkan   0.089 ms   0.099 ms   0.305 ms   <- cliff
    --   OpenGL   ~0 ms      ~0 ms      0.056 ms
    --
    -- That 0.3 ms is what pushed the frame past the budget love.run's ~1.5 ms
    -- sleep leaves, so the game started missing a cap it used to hold, and burnt
    -- GPU doing it. MSAA is player-facing (Options offers 8x and 16x, and 16
    -- gets granted as 8), so the renderer gives way rather than the setting.
    -- Revisit if a later 12.x fixes the Vulkan path — it is the better long-term
    -- backend, and this is one line.
    t.graphics.renderers = { "opengl" }

    t.window.title = "TD Idle"
    -- t.window.icon = "assets/icon.png"
    t.window.width = 1280
    t.window.height = 720
    t.window.resizable = false
    t.window.vsync = 0            -- 0 = off, 1 = on, -1 = adaptive
    t.window.msaa = 4     -- multisample antialiasing samples (smooths circles/rounded corners)
    t.window.fullscreen = false

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