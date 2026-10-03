--- A dead entity's last pose fading out, with a burst.

local Particles = require("particles")
local Tile = require("game.tile")
local UI = require("ui")

local DeathEffect = {}
DeathEffect.__index = DeathEffect

local FADE = 0.6

local BURST = {
    countMin = 22, countMax = 30,
    sizeMin = 1.2, sizeMax = 3.2,
    speedMin = 60, speedMax = 240,
    lifeMin = 0.35, lifeMax = 0.8,
    drag = 4,
}

---@param entity table # already dead; read for its look
---@return table
function DeathEffect.new(entity)
    local self = setmetatable({
        entity = entity,
        x = entity.x, y = entity.y, angle = entity.angle,
        t = 0,
        burst = Particles.Burst.new(BURST),
    }, DeathEffect)
    self.burst:spawn(self.x, self.y, entity:color())
    self.burst:spawn(self.x, self.y, UI.Theme.colors.highlight, 0.6)
    return self
end

---@return boolean
function DeathEffect:done()
    return self.t >= FADE and #self.burst.particles == 0
end

---@param dt number
function DeathEffect:update(dt)
    self.t = self.t + dt
    self.burst:update(dt)
end

function DeathEffect:draw()
    if self.t < FADE then self.entity:drawBody(self.x, self.y, self.angle, 1 - self.t / FADE) end
    love.graphics.push("all")
    love.graphics.scale(Tile.worldScale())
    self.burst:draw()
    love.graphics.pop()
end

return DeathEffect
