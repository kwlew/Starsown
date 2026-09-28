local Globals = {}

Globals.game = {
    name      = "Starsown",
    version   = "0.3.0",
    startedAt = 0,
}

--- stamps the session start and seeds the RNG from it; call once at boot
function Globals.init()
    Globals.game.startedAt = os.time()
    math.randomseed(Globals.game.startedAt)
end

return Globals
