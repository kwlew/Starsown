local Particles = require "lib.particles"

local Globals   = {}

Globals.game = {
    name        = "TD Idle",
    version     = "0.0.1",
    startedAt   = 0,
}

Globals.menu = {
    Particles = {
        starfield = Particles.Starfield.new{
            burst = Particles.Burst.new {
            countMin   = 10, countMax       = 15,
            sizeMin    = 0.1, sizeMax       = 2.5,
            speedMin   = 50, speedMax       = 200,
            lifeMin    = 0.35, lifeMax      = 0.75,
            drag       = 5,            
        },
        embers = Particles.Burst.new {
            countMin   = 1, countMax        = 3,
            sizeMin    = 0.5, sizeMax       = 1.0,
            speedMin   = 20, speedMax       = 60,
            lifeMin    = 0.35, lifeMax      = 0.75,
            drag       = 15,
        },
        clickRadius    = 16,
        timer          = 0,
        spawnMin       = 0.4, spawnMax      = 1.3,
        speedMin       = 100, speedMax      = 350,
        lengthMin      = 100, lengthMax     = 400,
        lifeMin        = 1.5, lifeMax       = 5.2,
        dyingThreshold = 0.4,
        -- Golden stars.
        goldenChance   = 0.33,
        goldenSpeedMin = 70, goldenSpeedMax = 150,
        goldenLifeMin  = 4, goldenLifeMax   = 13,
        },
    }
}

function Globals.init()
    Globals.game.startedAt = os.time()
    math.randomseed(Globals.game.startedAt)
end

function Globals.menuBurst()
    return Globals.menu.Particles.burst
end

function Globals.menuEmbers()
    return Globals.menu.Particles.embers
end

return Globals