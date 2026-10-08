--- Shooting stars: click to pop, the rest burn out.

local Debris = require("particles.starfield.debris")
local Look = require("particles.starfield.look")
local Math = require("utils.math")
local Motion = require("ui.core.motion")
local Shower = require("particles.starfield.shower")
local Sprites = require("particles.starfield.sprites")
local StarPop = require("particles.starPop")
local Theme = require("ui.core.theme")
local Trails = require("particles.starfield.trails")

local Starfield = {}
Starfield.__index = Starfield

local REDUCED_SPAWN_SCALE = 2.5
local REDUCED_SPEED_SCALE = 0.5

local TWINKLE = { amount = 0.18, speedMin = 5.5, speedMax = 9.5 }
local SPECIAL_TWINKLE = { amount = 0.34, speedMin = 2.4, speedMax = 3.6 }
local SPECIAL_SCALE = 1.7

-- depth 0 is far: small, slow, dim; 1 is near
local DEPTH_BIAS = 1.6 -- > 1 leans toward far
local FAR_SCALE, FAR_SPEED, FAR_LENGTH, FAR_BRIGHTNESS = 0.55, 0.5, 0.6, 0.45

local POP_FADE = 0.3       -- s a popped trail lingers, crumbling
local CULL_MARGIN = 64
local DYING_RETRACT = 0.65 -- trail pulled in while burning out
local HIT_TRAIL = 48       -- px of trail behind the head that also counts as a hit

local GLOW_SIZE = 4
local HEAD_RADIUS = 2
local HEAD_SWELL = 1.6 -- px per unit of flare
local CORE_FRAC = 0.55
local CORE_ALPHA = 0.85

---@param far number
---@param depth number # 0..1
---@return number
local function byDepth(far, depth)
    return far + (1 - far) * depth
end

---@param config? table # timings and ranges; `pop` goes to StarPop.new, `embers` to Debris.new,
--   `shower` to Shower.new
---@return table
function Starfield.new(config)
    config = config or {}
    return setmetatable({
        stars = {},
        pop = StarPop.new(config.pop),
        debris = Debris.new{ embers = config.embers },
        shower = Shower.new(config.shower),
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

--- one streak from the top, heading down-right unless told otherwise;
--- specials are slower, larger, and always near
---@param angle? number # heading, radians
function Starfield:spawnStar(angle)
    local w, h = love.graphics.getDimensions()
    local golden = math.random() < self.goldenChance
    local rainbow = not golden and math.random() < self.rainbowChance
    local special = golden or rainbow
    local twinkle = special and SPECIAL_TWINKLE or TWINKLE
    local depth = special and 1 or math.random() ^ DEPTH_BIAS

    local speed = special and Math.randRange(self.goldenSpeedMin, self.goldenSpeedMax)
        or Math.randRange(self.speedMin, self.speedMax) * byDepth(FAR_SPEED, depth)
    if Motion.reduced then speed = speed * REDUCED_SPEED_SCALE end
    local maxLife = special and Math.randRange(self.goldenLifeMin, self.goldenLifeMax)
        or Math.randRange(self.lifeMin, self.lifeMax)
    angle = angle or math.rad(Math.randRange(42, 48))
    local dirX, dirY = math.cos(angle), math.sin(angle)
    local x = Math.randRange(-0.05 * w, 0.65 * w)
    if dirX < 0 then x = w - x end -- heading left: start from the right

    self.stars[#self.stars + 1] = {
        x = x,
        y = Math.randRange(-0.05 * h, 0.03 * h),
        dirX = dirX, dirY = dirY,
        speed = speed,
        travelled = 0,
        length = Math.randRange(self.lengthMin, self.lengthMax) * byDepth(FAR_LENGTH, depth),
        life = 0,
        maxLife = maxLife,
        golden = golden,
        rainbow = rainbow,
        color = golden and Theme.fixedColors.gold or Theme.colors.star,
        flare = golden and Theme.fixedColors.goldFlare or Theme.colors.accentAlt,
        twinklePhase = Math.randAngle(),
        twinkleSpeed = Math.randRange(twinkle.speedMin, twinkle.speedMax),
        twinkleAmount = twinkle.amount,
        scale = special and SPECIAL_SCALE or byDepth(FAR_SCALE, depth),
        brightness = byDepth(FAR_BRIGHTNESS, depth),
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
    self.debris:ember(s, self:speedOf(s))
end

--- current px/s; burning out slows it down
---@param s table
---@return number
function Starfield:speedOf(s)
    return s.speed * (1 - Look.dying(s, self.dyingThreshold) * 0.95)
end

--- px of trail drawn behind the head right now
---@param s table
---@return number
function Starfield:trailLength(s)
    local dying = Look.dying(s, self.dyingThreshold)
    return math.min(s.length, s.travelled) * (1 - dying * DYING_RETRACT)
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
    local speed = self:speedOf(s)
    local distance = speed * dt
    s.x, s.y = s.x + s.dirX * distance, s.y + s.dirY * distance
    s.travelled = s.travelled + distance

    if s.golden or s.rainbow then
        local fade, _, r, g, b = Look.of(s, Look.dying(s, self.dyingThreshold))
        self.debris:shed(s, dt, speed, fade, r, g, b)
    end

    if s.life >= s.maxLife then
        self:expire(s)
        return false
    end
    return not offScreen(s, w, h)
end

--- a shower star when one is due; otherwise the steady trickle
---@param dt number
function Starfield:spawnNext(dt)
    local showerAngle = self.shower:update(dt)
    if showerAngle then self:spawnStar(showerAngle) end
    if self.shower:active() then return end -- the shower has the sky to itself

    self.timer = self.timer - dt
    if self.timer <= 0 then
        self.timer = Math.randRange(self.spawnMin, self.spawnMax) * (Motion.reduced and REDUCED_SPAWN_SCALE or 1)
        self:spawnStar()
    end
end

---@param dt number
function Starfield:update(dt)
    self:spawnNext(dt)

    local w, h = love.graphics.getDimensions()
    for i = #self.stars, 1, -1 do
        if not self:advance(self.stars[i], dt, w, h) then table.remove(self.stars, i) end
    end

    self.pop:update(dt)
    self.debris:update(dt)
end

--- px from the point to the head, or the stretch of trail just behind it
---@param s table
---@return number
function Starfield:distanceTo(s, x, y)
    local behind = -((x - s.x) * s.dirX + (y - s.y) * s.dirY)
    behind = Math.clamp(behind, 0, math.min(HIT_TRAIL * s.scale, self:trailLength(s)))
    return Math.length(x - (s.x - s.dirX * behind), y - (s.y - s.dirY * behind))
end

--- pops the star nearest the point, if any is within reach
---@param x number
---@param y number
---@return table|nil star # { golden, rainbow } of what popped
function Starfield:popAt(x, y)
    local best, bestDistance = nil, self.clickRadius
    for _, s in ipairs(self.stars) do
        if not s.popped then
            local distance = self:distanceTo(s, x, y)
            if distance <= bestDistance then best, bestDistance = s, distance end
        end
    end
    if not best then return nil end

    local s, speed = best, self:speedOf(best)
    local _, _, r, g, b = Look.of(s, Look.dying(s, self.dyingThreshold))
    self.pop:spawn(s.x, s.y, {
        color = s.golden and s.color or Theme.fixedColors.starPop,
        scale = (0.8 + s.speed / self.speedMax * 0.4) * s.scale,
        vx = s.dirX * speed, vy = s.dirY * speed,
        golden = s.golden, rainbow = s.rainbow,
    })
    self.debris:crumble(s, self:trailLength(s), r, g, b)
    s.popped = 0
    return s
end

---@param s table
function Starfield:queue(s)
    local dying = Look.dying(s, self.dyingThreshold)
    local fade, glow, r, g, b = Look.of(s, dying)
    local length = self:trailLength(s)

    if s.popped then
        local k = 1 - s.popped / POP_FADE
        if length >= 1 then Trails.add(s, length, r, g, b, fade * k * k) end
        return
    end

    local flicker = Look.flicker(s)
    local m = Theme.metrics
    Sprites.glow(s.x, s.y, GLOW_SIZE * s.scale + m.glowLayers * m.glowSpread,
        r, g, b, Math.clamp01(glow * flicker * 0.5 * s.brightness))

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
    self.debris:draw()
    self.pop:draw(true)
    love.graphics.pop()
end

return Starfield
