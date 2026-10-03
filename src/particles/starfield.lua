--- Shooting stars: click to pop, the rest burn out.

local Burst = require("particles.burst")
local Look = require("particles.starfield.look")
local Math = require("utils.math")
local Motion = require("ui.core.motion")
local Sprites = require("particles.starfield.sprites")
local Theme = require("ui.core.theme")
local Trails = require("particles.starfield.trails")

local Starfield = {}
Starfield.__index = Starfield

local REDUCED_SPAWN_SCALE = 2.5
local REDUCED_SPEED_SCALE = 0.5

local TWINKLE = { amount = 0.18, speedMin = 5.5, speedMax = 9.5 }
local SPECIAL_TWINKLE = { amount = 0.34, speedMin = 2.4, speedMax = 3.6 }
local SPECIAL_SCALE = 1.7

local POP_FADE = 0.7       -- s a popped trail lingers
local CULL_MARGIN = 64
local DYING_RETRACT = 0.65 -- trail pulled in while burning out

local GLOW_SIZE = 4
local HEAD_RADIUS = 2
local HEAD_SWELL = 1.6 -- px per unit of flare
local CORE_FRAC = 0.55
local CORE_ALPHA = 0.85

local EMBERS = {
    countMin = 4, countMax = 7,
    speedMin = 14, speedMax = 60,
    lifeMin = 0.25, lifeMax = 0.55,
    sizeMin = 1, sizeMax = 2,
    drag = 5,
}

---@param base table
---@param override? table
---@return table
local function merged(base, override)
    local out = {}
    for key, value in pairs(base) do out[key] = value end
    for key, value in pairs(override or {}) do out[key] = value end
    return out
end

---@param config? table # timings and ranges; `burst`, `embers` go to Burst.new
---@return table
function Starfield.new(config)
    config = config or {}
    return setmetatable({
        stars = {},
        burst = Burst.new(config.burst),
        embers = Burst.new(merged(EMBERS, config.embers)),
        clickRadius = config.clickRadius or 20,
        timer = 0,
        spawnMin = config.spawnMin or 0.4,
        spawnMax = config.spawnMax or 1.5,
        speedMin = config.speedMin or 100,
        speedMax = config.speedMax or 450,
        lengthMin = config.lengthMin or 120,
        lengthMax = config.lengthMax or 500,
        lifeMin = config.lifeMin or 1.5,
        lifeMax = config.lifeMax or 5.2,
        dyingThreshold = config.dyingThreshold or 0.5,
        goldenChance = config.goldenChance or 0.003,
        goldenSpeedMin = config.goldenSpeedMin or 70,
        goldenSpeedMax = config.goldenSpeedMax or 110,
        goldenLifeMin = config.goldenLifeMin or 9,
        goldenLifeMax = config.goldenLifeMax or 13,
        rainbowChance = config.rainbowChance or 0.001,
    }, Starfield)
end

--- one streak from the upper left; specials are slower, larger
function Starfield:spawnStar()
    local w, h = love.graphics.getDimensions()
    local golden = math.random() < self.goldenChance
    local rainbow = not golden and math.random() < self.rainbowChance
    local special = golden or rainbow
    local twinkle = special and SPECIAL_TWINKLE or TWINKLE

    local speed = special and Math.randRange(self.goldenSpeedMin, self.goldenSpeedMax)
        or Math.randRange(self.speedMin, self.speedMax)
    if Motion.reduced then speed = speed * REDUCED_SPEED_SCALE end
    local maxLife = special and Math.randRange(self.goldenLifeMin, self.goldenLifeMax)
        or Math.randRange(self.lifeMin, self.lifeMax)
    local angle = math.rad(Math.randRange(42, 48))

    self.stars[#self.stars + 1] = {
        x = Math.randRange(-0.05 * w, 0.65 * w),
        y = Math.randRange(-0.05 * h, 0.03 * h),
        dirX = math.cos(angle), dirY = math.sin(angle),
        speed = speed,
        travelled = 0,
        length = Math.randRange(self.lengthMin, self.lengthMax),
        life = 0,
        maxLife = maxLife,
        golden = golden,
        rainbow = rainbow,
        color = golden and Theme.fixedColors.gold or Theme.colors.star,
        flare = golden and Theme.fixedColors.goldFlare or Theme.colors.accentAlt,
        twinklePhase = Math.randAngle(),
        twinkleSpeed = Math.randRange(twinkle.speedMin, twinkle.speedMax),
        twinkleAmount = twinkle.amount,
        scale = special and SPECIAL_SCALE or 1,
    }
end

--- true once the tail has left the window too
---@param s table
---@return boolean
local function offScreen(s, w, h)
    local length = math.min(s.length, s.travelled)
    local tailX, tailY = s.x - s.dirX * length, s.y - s.dirY * length
    local right, bottom = w + CULL_MARGIN, h + CULL_MARGIN
    return (s.dirX > 0 and s.x > right and tailX > right)
        or (s.dirY > 0 and s.y > bottom and tailY > bottom)
        or (s.dirX < 0 and s.x < -CULL_MARGIN and tailX < -CULL_MARGIN)
        or (s.dirY < 0 and s.y < -CULL_MARGIN and tailY < -CULL_MARGIN)
end

--- burning out on screen leaves a puff of embers
---@param s table
function Starfield:expire(s)
    local w, h = love.graphics.getDimensions()
    if s.x < 0 or s.x > w or s.y < 0 or s.y > h then return end
    self.embers:spawn(s.x, s.y, s.flare, s.scale * ((s.golden or s.rainbow) and 2 or 1))
end

---@param s table
---@param dt number
---@return boolean alive
function Starfield:advance(s, dt, w, h)
    if s.popped then
        s.popped = s.popped + dt
        return s.popped < POP_FADE
    end

    s.life = s.life + dt
    s.twinklePhase = s.twinklePhase + s.twinkleSpeed * dt
    local distance = s.speed * (1 - Look.dying(s, self.dyingThreshold) * 0.95) * dt
    s.x, s.y = s.x + s.dirX * distance, s.y + s.dirY * distance
    s.travelled = s.travelled + distance

    if s.life >= s.maxLife then
        self:expire(s)
        return false
    end
    return not offScreen(s, w, h)
end

---@param dt number
function Starfield:update(dt)
    self.timer = self.timer - dt
    if self.timer <= 0 then
        self.timer = Math.randRange(self.spawnMin, self.spawnMax) * (Motion.reduced and REDUCED_SPAWN_SCALE or 1)
        self:spawnStar()
    end

    local w, h = love.graphics.getDimensions()
    for i = #self.stars, 1, -1 do
        if not self:advance(self.stars[i], dt, w, h) then table.remove(self.stars, i) end
    end

    self.burst:update(dt)
    self.embers:update(dt)
end

--- pops the topmost star under the point
---@param x number
---@param y number
---@return table|nil star # { golden, rainbow } of what popped
function Starfield:popAt(x, y)
    local r2 = self.clickRadius * self.clickRadius
    for i = #self.stars, 1, -1 do -- later stars draw on top
        local s = self.stars[i]
        local dx, dy = s.x - x, s.y - y
        if not s.popped and dx * dx + dy * dy <= r2 then
            local debris = s.golden and s.color or Theme.fixedColors.starPop
            self.burst:spawn(s.x, s.y, debris, (0.8 + s.speed / self.speedMax * 0.4) * s.scale)
            s.popped = 0
            return s
        end
    end
end

---@param s table
function Starfield:queue(s)
    local travelled = math.min(s.length, s.travelled)
    local dying = Look.dying(s, self.dyingThreshold)
    local fade, glow, r, g, b = Look.of(s, dying)

    if s.popped then
        local k = 1 - s.popped / POP_FADE
        if travelled >= 1 then Trails.add(s, travelled, r, g, b, fade * k * k) end
        return
    end

    local flicker = Look.flicker(s)
    local m = Theme.metrics
    Sprites.glow(s.x, s.y, GLOW_SIZE * s.scale + m.glowLayers * m.glowSpread,
        r, g, b, Math.clamp01(glow * flicker * 0.5))

    local length = travelled * (1 - dying * DYING_RETRACT)
    if length >= 1 then Trails.add(s, length, r, g, b, fade) end

    local alpha = Math.clamp01(fade * flicker)
    local radius = (HEAD_RADIUS + math.max(0, glow - 1) * HEAD_SWELL) * s.scale
    Sprites.head(s.x, s.y, radius, r, g, b, alpha)
    Sprites.head(s.x, s.y, radius * CORE_FRAC, 1, 1, 1, alpha * CORE_ALPHA)
end

--- everything additive, in a handful of draw calls
function Starfield:draw()
    Trails.reserve(#self.stars)
    Sprites.begin(#self.stars)
    for _, s in ipairs(self.stars) do
        if s.speed > 0 then self:queue(s) end
    end

    love.graphics.push("all")
    love.graphics.setBlendMode("add")
    love.graphics.setColor(1, 1, 1, 1)
    Sprites.drawGlows()
    Trails.flush()
    Sprites.drawHeads()
    self.embers:draw(true)
    self.burst:draw(true)
    love.graphics.pop()
end

return Starfield
