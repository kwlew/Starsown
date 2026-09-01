-- Headless launch target for build.ps1's -Bytecode step. No window, no
-- audio/joystick/physics -- this only ever mounts a real directory and dumps
-- bytecode, so every module that isn't love.filesystem is dead weight here.
function love.conf(t)
    t.window = false
    t.modules.window = false
    t.modules.graphics = false
    t.modules.audio = false
    t.modules.joystick = false
    t.modules.physics = false
    t.console = true -- so print() is visible even if this is ever run with love.exe instead of lovec.exe
end
