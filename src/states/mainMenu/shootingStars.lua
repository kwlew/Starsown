--- The clickable shooting stars behind the menu.

local Globals = require("globals")
local Particles = require("particles")
local Sounds = require("core.audio.sounds")
local Stats = require("services.stats")

local ShootingStars = {}

local COMBO_WINDOW = 1.5 -- s between pops that keeps a combo going
local COMBO_STEPS = 8    -- semitones the pitch climbs, at most

local combo, lastPop = 0, -math.huge

local CONFIG = {
    embers = {
        countMin = 1, countMax = 7,
        sizeMin = 0.5, sizeMax = 1.0,
        speedMin = 20, speedMax = 60,
        lifeMin = 0.35, lifeMax = 0.75,
        drag = 15,
        gravity = 10,
    },
    clickRadius = 16,
    spawnMin = 0.4, spawnMax = 1.3,
    speedMin = 100, speedMax = 350,
    lengthMin = 100, lengthMax = 400,
    lifeMin = 1.5, lifeMax = 5.2,
    dyingThreshold = 0.6,
    goldenChance = Globals.shootingStars.goldenChance,
    goldenSpeedMin = 70, goldenSpeedMax = 150,
    goldenLifeMin = 4, goldenLifeMax = 13,
    rainbowChance = Globals.shootingStars.rainbowChance,
    shower = {
        intervalMin = Globals.shootingStars.showerIntervalMin,
        intervalMax = Globals.shootingStars.showerIntervalMax,
    },
}

--- one semitone higher per quick pop in a row
---@return number pitch
local function comboPitch()
    local now = love.timer.getTime()
    combo = now - lastPop <= COMBO_WINDOW and combo + 1 or 0
    lastPop = now
    return 2 ^ (math.min(combo, COMBO_STEPS) / 12)
end

---@return table # a Particles.Starfield
function ShootingStars.new()
    return Particles.Starfield.new(CONFIG)
end

--- pops the clicked star: sound, pitched up by a combo, plus a stats count
---@param field table
---@param x number
---@param y number
---@return boolean popped
function ShootingStars.click(field, x, y)
    local star = field:popAt(x, y)
    if not star then return false end
    Sounds.starPop(star.golden, comboPitch())
    Stats.pop(star.rainbow and "rainbow" or star.golden and "golden" or nil)
    return true
end

return ShootingStars
