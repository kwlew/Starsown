--- The clickable shooting stars behind the menu.

local Particles = require("particles")
local Sounds = require("core.audio.sounds")
local Stats = require("services.stats")

local ShootingStars = {}

local CONFIG = {
    burst = {
        countMin = 10, countMax = 50,
        sizeMin = 0.1, sizeMax = 2.5,
        speedMin = 50, speedMax = 200,
        lifeMin = 0.35, lifeMax = 0.75,
        drag = 5,
    },
    embers = {
        countMin = 1, countMax = 7,
        sizeMin = 0.5, sizeMax = 1.0,
        speedMin = 20, speedMax = 60,
        lifeMin = 0.35, lifeMax = 0.75,
        drag = 15,
    },
    clickRadius = 16,
    spawnMin = 0.4, spawnMax = 1.3,
    speedMin = 100, speedMax = 350,
    lengthMin = 100, lengthMax = 400,
    lifeMin = 1.5, lifeMax = 5.2,
    dyingThreshold = 0.6,
    goldenChance = 0.004, -- about 1 in 250
    goldenSpeedMin = 70, goldenSpeedMax = 150,
    goldenLifeMin = 4, goldenLifeMax = 13,
    rainbowChance = 0.001, -- about 1 in 1000
}

---@return table # a Particles.Starfield
function ShootingStars.new()
    return Particles.Starfield.new(CONFIG)
end

--- pops the clicked star: sound plus a stats count
---@param field table
---@param x number
---@param y number
---@return boolean popped
function ShootingStars.click(field, x, y)
    local star = field:popAt(x, y)
    if not star then return false end
    Sounds.starPop(star.golden)
    Stats.pop(star.rainbow and "rainbow" or star.golden and "golden" or nil)
    return true
end

return ShootingStars
