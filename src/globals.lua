local Globals = {}

Globals.game = {
    name = "TD Idle",
    version = "0.0.1",
    startedAt = 0,
}

function Globals.init()
    Globals.game.startedAt = os.time()
    math.randomseed(Globals.game.startedAt)
end

return Globals