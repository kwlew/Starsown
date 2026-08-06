-- tests/smoke/conf.lua
-- The harness's own window config. Deliberately nothing like the game's: a
-- small window, no msaa, no saved-settings read. The game's conf.lua is
-- exercised separately, by hand, in main.lua -- see the note there.
function love.conf(t)
    t.identity = "TD-Idle-smoke" -- never the game's save directory
    t.version = "11.5"
    t.console = false

    t.window.title = "TD Idle (smoke test)"
    t.window.width = 640
    t.window.height = 360
    t.window.resizable = false
    t.window.vsync = 0   -- no frame pacing: the harness should finish fast
    t.window.msaa = 0    -- software GL on a CI box has no business doing 4x
    t.window.highdpi = false

    t.modules.joystick = false
    t.modules.physics = false
end
