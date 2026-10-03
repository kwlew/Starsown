--- A melee arc: swing() starts it, update() sweeps and hits.
-- Each target is hit at most once per swing.

local Math = require("utils.math")
local Particles = require("particles")
local Render = require("game.swipe.render")
local UI = require("ui")

local Swipe = {
    ARC = math.pi * 0.8,
    INNER = 16, -- the arc starts outside the body
    REACH = 54, -- about where the sword tip lands
}
Swipe.__index = Swipe

local DURATION = 0.24 -- to cross the arc
local AFTERGLOW = 0.05
local COOLDOWN = 0.40
local SPARK_INTERVAL = 0.012
local SPARK_SCALE = 0.6

local SPARKS = {
    countMin = 2, countMax = 4,
    sizeMin = 0.6, sizeMax = 1.8,
    speedMin = 30, speedMax = 140,
    lifeMin = 0.12, lifeMax = 0.32,
    drag = 7,
}
local IMPACT = {
    countMin = 10, countMax = 16,
    sizeMin = 1.0, sizeMax = 2.8,
    speedMin = 90, speedMax = 280,
    lifeMin = 0.20, lifeMax = 0.50,
    drag = 5,
}

---@param config? table # { damage?, knockback? }
---@return table
function Swipe.new(config)
    config = config or {}
    return setmetatable({
        damage = config.damage or 1,
        knockback = config.knockback or 280,
        sparks = Particles.Burst.new(SPARKS),
        impact = Particles.Burst.new(IMPACT),
        x = 0, y = 0,
        angle = 0,
        dir = 1, -- flips per swing, so swings mirror
        active = false,
        t = 0,
        cooldown = 0,
        sparkTimer = 0,
        hit = {},
    }, Swipe)
end

---@return boolean
function Swipe:ready()
    return self.cooldown <= 0 and not self.active
end

--- safe every frame; the cooldown paces swings
---@param angle number # centre of the sweep
---@return boolean started
function Swipe:swing(angle)
    if not self:ready() then return false end
    self.angle, self.dir = angle, -self.dir
    self.active, self.t, self.cooldown, self.sparkTimer = true, 0, COOLDOWN, 0
    self.hit = {}
    return true
end

---@return number # 0..1 across the arc
function Swipe:progress()
    return math.min(1, self.t / DURATION)
end

---@return number # leading edge offset, -ARC/2..ARC/2
function Swipe:bladeOffset()
    return self.ARC * (self:progress() - 0.5)
end

---@return number # radians
function Swipe:bladeAngle()
    return self.angle + self.dir * self:bladeOffset()
end

---@return number # 0..1 through the afterglow
function Swipe:fade()
    local past = self.t - DURATION
    return past <= 0 and 1 or math.max(0, 1 - past / AFTERGLOW)
end

--- whether the leading edge has reached `target` yet
---@param target table
---@return boolean
function Swipe:reaches(target)
    local dx, dy = target.x - self.x, target.y - self.y
    local distance = Math.length(dx, dy)
    if distance > self.REACH + target.radius then return false end
    local slack = math.atan(target.radius / math.max(distance, 1))
    local offset = Math.angleDiff(self.angle, math.atan2(dy, dx)) * self.dir
    return offset >= -self.ARC / 2 - slack and offset <= self:bladeOffset() + slack
end

---@param target table
---@param owner table
function Swipe:strike(target, owner)
    self.hit[target] = true
    if not target:damage(self.damage, owner) then return end
    target:knockback(self.x, self.y, self.knockback)
    local dx, dy = target.x - self.x, target.y - self.y
    local distance = math.max(Math.length(dx, dy), 0.001)
    local edge = distance - target.radius
    self.impact:spawn(self.x + dx / distance * edge, self.y + dy / distance * edge, UI.Theme.colors.danger)
end

--- sweeps across a crowd, not all at once
---@param world table
---@param owner table
function Swipe:resolve(world, owner)
    for target in world:each() do
        if target ~= owner and target.kind ~= "player" and not self.hit[target] and self:reaches(target) then
            self:strike(target, owner)
        end
    end
end

--- at a fixed interval, independent of frame rate
---@param dt number
function Swipe:emitSparks(dt)
    if self:progress() >= 1 then return end
    self.sparkTimer = self.sparkTimer + dt
    while self.sparkTimer >= SPARK_INTERVAL do
        self.sparkTimer = self.sparkTimer - SPARK_INTERVAL
        local x, y = Math.polar(self.x, self.y, self:bladeAngle(), Math.randRange(self.INNER, self.REACH))
        self.sparks:spawn(x, y, UI.Theme.colors.highlight, SPARK_SCALE)
    end
end

--- per frame, from the owner's drawn position
---@param dt number
---@param world table
---@param owner table # never hit by its own swing
function Swipe:update(dt, x, y, world, owner)
    self.x, self.y = x, y
    self.cooldown = math.max(0, self.cooldown - dt)
    self.sparks:update(dt)
    self.impact:update(dt)
    if not self.active then return end

    self.t = self.t + dt
    self:resolve(world, owner)
    self:emitSparks(dt)
    if self.t >= DURATION + AFTERGLOW then self.active = false end
end

function Swipe:draw()
    Render.draw(self)
end

return Swipe
