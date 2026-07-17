-- conf.lua
function love.conf(t)
    t.identity = "my-game"          -- save-directory name (love.filesystem writes here)
    t.version = "11.5"              -- LÖVE version this game targets
    t.console = true              -- Windows: opens a console window for print()

    t.window.title = "My Game"
    -- t.window.icon = "assets/icon.png"
    t.window.width = 1280
    t.window.height = 720
    t.window.resizable = true
    t.window.vsync = 0            -- 0 = off, 1 = on, -1 = adaptive
    t.window.msaa = 0               -- multisample antialiasing samples
    t.window.fullscreen = false
    t.window.highdpi = true         -- retina/hidpi support

    -- Disable modules you don't use — saves startup time and memory
    t.modules.joystick = false
    t.modules.physics = false
end