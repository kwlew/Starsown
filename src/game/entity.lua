--- Base of every world actor. Types extend it, overriding hooks.
-- Units are design px; (x, y) centres hitbox and sprite.

local Body = require("game.entity.body")
local Health = require("game.entity.health")
local Math = require("utils.math")
local Movement = require("game.entity.movement")
local Tile = require("game.tile")

local Entity = {
    name = "entity",
    kind = "entity", -- "player", "passive", "hostile", "projectile"
    radius = Tile.px(0.45),
    solid = true,  -- pushed apart from other solids
    mass = 1,      -- the lighter one gives way more
    deathEffect = true,
    maxSpeed = 0,
    accel = 9,     -- exponential steering rates
    decel = 10,
    maxHealth = 1,
    invulnerableTime = 0.2, -- after a hit; also its flicker
    texture = nil,
    tint = nil,    -- theme role for greyscale art
    fallbackColor = "accent",
    spriteAngle = -math.pi / 2, -- art faces up
    facesMovement = true,
    turnRate = 10,
}
Entity.__index = Entity

for _, mixin in ipairs({ Movement, Health, Body }) do
    for name, fn in pairs(mixin) do Entity[name] = fn end
end

--- a new type inheriting from this one
---@param def? table
---@return table
function Entity:extend(def)
    def = def or {}
    def.__index = def
    def.super = self
    return setmetatable(def, self)
end

---@param opts? table # passed to init
---@return table
function Entity:new(x, y, opts)
    local angle = Math.randAngle()
    local e = setmetatable({
        x = x, y = y, prevX = x, prevY = y,
        vx = 0, vy = 0,
        angle = angle, prevAngle = angle,
        moveX = 0, moveY = 0,
        speed = self.maxSpeed,
        health = self.maxHealth,
        invulnerable = 0,
        alive = true,
    }, self)
    e:init(opts or {})
    return e
end

---@return boolean # alive and in a world
function Entity:isValid()
    return self.alive and self.world ~= nil
end

--- hooks; the base versions do nothing
function Entity:init(opts) end
--- sets moveX/moveY/speed: input and AI
function Entity:think(dt, world) end
--- every frame, for things that mustn't lag a tick
function Entity:frame(dt, world, alpha) end
--- drawn after every entity
function Entity:drawEffects(alpha) end

--- one fixed step
---@param dt number
---@param world table
function Entity:tick(dt, world)
    self.prevX, self.prevY, self.prevAngle = self.x, self.y, self.angle
    self.invulnerable = math.max(0, self.invulnerable - dt)
    self:think(dt, world)
    self:steer(dt)
    if self.facesMovement then self:turn(dt) end
    self.x, self.y = self.x + self.vx * dt, self.y + self.vy * dt
    self:clamp(world)
end

return Entity
