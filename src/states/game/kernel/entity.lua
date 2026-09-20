-- src/states/game/kernel/entity.lua
-- This will be the base entity class.
-- All entities will inherit from this class.

local UI = require "ui"
local Math = require "utils.math"
local Palette = require "states.game.rendering.palette"
local Perspective = require "states.game.rendering.perspective"
local Shape = require "states.game.rendering.shape"
local Units = require "states.game.units"

local Entity = {}
Entity.__index = Entity

local GRAVITY = 25 -- m/s^2
local KNOCKBACK_DRAG = 9
local HIT_FLASH_TIME = 0.3

local STAGGER_TIME = 0.12
local OUTLINE_WIDTH = Units.px(3)

local HP_BAR_HEIGHT = Units.px(7)
local HP_BAR_GAP = Units.px(9)
local HP_BAR_WIDTH = 2.5 -- in radii
local HP_BAR_ALPHA = 0.85
local HP_BAR_ROUNDING = Units.px(3)
local HP_BAR_INSET = Units.px(1)
local HP_BAR_GLOSS = 0.22
local HP_FRONT_RATE = 14
local HP_TRAIL_RATE = 5
local HP_TRAIL_DELAY = 0.45

function Entity.extend()
    local class = setmetatable({}, { __index = Entity })
    class.__index = class
    return class
end
--- Initialize a new entity.
---@param self any
---@param config any
---@return table
function Entity.init(self, config)
    self.x = config.x or 0
    self.y = config.y or 0
    self.z = config.z or 0
    self.radius = config.radius or Units.px(12)
    self.sides = config.sides
    self.color = config.color or Palette.entity.Default.color
    self.hp = config.hp or 10
    self.maxHp = config.maxHp or self.hp
    self.hpFront, self.hpTrail, self.trailDelay = self.hp, self.hp, 0
    self.facing = config.facing or 0
    self.vx, self.vy = 0, 0
    self.vz = 0
    self.kx, self.ky, self.kz = 0, 0, 0 -- knockback vel.
    self.flash = 0
    self.stagger = 0
    self.dead = false
    return self
end

---Create a new entity with the given config.
---@param config metatable
---@return table
function Entity.new(config)
    return Entity.init(setmetatable({}, Entity), config or {})
end

--- Damages the entity
---@param amount integer
---@param knockX any knockback in the x direction
---@param knockY any knockback in the y direction
---@param knockZ any knockback in the z direction
---@return boolean 
function Entity:damage(amount, knockX, knockY, knockZ)
    if self.dead then return false end

    self.hp = self.hp - amount
    self.flash = HIT_FLASH_TIME
    self.trailDelay = HP_TRAIL_DELAY
    self.stagger = STAGGER_TIME
    self.kx = self.kx + (knockX or 0)
    self.ky = self.ky + (knockY or 0)
    self.vz = self.vz + (knockZ or 0)
    if self.hp <= 0 then self.dead = true end
    return true
end

--- Restores health, up to maxHp.
---@param amount number
function Entity:heal(amount)
    if self.dead then return end
    self.hp = math.min(self.maxHp, self.hp + amount)
end

--- Updates the entity's state.
---@param dt number The time elapsed since the last update.
function Entity:update(dt)
    self.flash = math.max(0, self.flash - dt)
    self.stagger = math.max(0, self.stagger - dt)
    self.hpFront = Math.damp(self.hpFront, self.hp, HP_FRONT_RATE, dt)
    self.trailDelay = math.max(0, self.trailDelay - dt)
    if self.hpTrail < self.hpFront then
        self.hpTrail = self.hpFront
    elseif self.trailDelay <= 0 then
        self.hpTrail = Math.damp(self.hpTrail, self.hpFront, HP_TRAIL_RATE, dt)
    end

    local decay = Math.decay(KNOCKBACK_DRAG, dt)
    self.kx, self.ky = self.kx * decay, self.ky * decay
    
    if self.z > 0 or self.vz ~= 0 then
        self.vz = self.vz - GRAVITY * dt
        self.z = self.z + self.vz * dt
        if self.z <= 0 then self.z, self.vz = 0, 0 end
    end
end

--- Returns positive if entity is airborne
---@return boolean
function Entity:airborne()
    return self.z > 0
end

--- Moves the entity by the given amount.
---@param dx number The amount to move in the x direction.
---@param dy number The amount to move in the y direction.
function Entity:moveby(dx, dy)
    self.x = self.x + dx
    self.y = self.y + dy
end

--- Returns the distance to another entity.
---@param other any
---@return number
---@return unknown
---@return unknown
function Entity:distanceTo(other)
    local dx, dy = other.x - self.x, other.y - self.y
    return Math.length(dx, dy), dx, dy
end

--- Returns how the entity should be drawn on the screen, taking into account its z position and radius.
---@return number 
function Entity:drawY()
    return self.y - self.radius * Perspective.STAND - Perspective.lift(self.z)
end

--- Draw the shadow of the entity.
function Entity:drawGround()
    local fade = Perspective.shadowFade(self.z)
    local radius = self.radius * Perspective.SHADOW_SPREAD * fade

    love.graphics.setColor(Palette.entity.Default.shadow[1],
    Palette.entity.Default.shadow[2],
    Palette.entity.Default.shadow[3],
    Perspective.SHADOW_ALPHA * fade)

    love.graphics.ellipse("fill", self.x, self.y, radius, radius * Perspective.SHADOW_SQUASH)
end


--- Returns the color of the entity's body.
---@return number
---@return number
---@return number
function Entity:bodyColor()
    local body = self.color
    if self.flash <= 0 then return body[1], body[2], body[3] end
    return UI.Theme.lerp(body, Palette.entity.flash, self.flash / HIT_FLASH_TIME)
end

--- Draw the entity.
function Entity:draw()
    local r, g, b = self:bodyColor()
    local y = self:drawY()
    local radius = self.radius * Perspective.scale(self.z)

    love.graphics.setColor(r, g, b)
    Shape.draw("fill", self.x, y, radius, self.sides, self.facing)

    love.graphics.setLineWidth(OUTLINE_WIDTH)
    UI.Theme.setColor(Palette.entity.Default.outline, 0.55)

    Shape.draw("line", self.x, y, radius, self.sides, self.facing)
    love.graphics.setLineWidth(Units.LINE)
    love.graphics.setColor(1, 1, 1, 1)
end

--- Draw a health bar above the entity's body: a rounded, outlined track with
-- the eased green fill, the yellow trail behind it and a faint gloss on top.
function Entity:drawHealth()
    local width = self.radius * HP_BAR_WIDTH
    local left = self.x - width / 2
    local top = self:drawY() - self.radius * Perspective.scale(self.z) - HP_BAR_GAP - HP_BAR_HEIGHT

    local ratio = Math.clamp01(self.hp / self.maxHp)
    local front = Math.clamp01(self.hpFront / self.maxHp)
    local trail = Math.clamp01(self.hpTrail / self.maxHp)

    local innerLeft, innerTop = left + HP_BAR_INSET, top + HP_BAR_INSET
    local innerWidth, innerHeight = width - HP_BAR_INSET * 2, HP_BAR_HEIGHT - HP_BAR_INSET * 2
    local rounding = HP_BAR_ROUNDING - HP_BAR_INSET

    local back = Palette.hp.back
    love.graphics.setColor(back[1], back[2], back[3], HP_BAR_ALPHA)
    love.graphics.rectangle("fill", left, top, width, HP_BAR_HEIGHT, HP_BAR_ROUNDING)

    UI.Theme.setColor(Palette.hp.trail)
    love.graphics.rectangle("fill", innerLeft, innerTop, innerWidth * trail, innerHeight, rounding)

    local r, g, b = UI.Theme.lerp(Palette.hp.low, Palette.hp.full, ratio)
    love.graphics.setColor(r, g, b)
    love.graphics.rectangle("fill", innerLeft, innerTop, innerWidth * front, innerHeight, rounding)

    if innerWidth * front > rounding * 2 then
        love.graphics.setColor(1, 1, 1, HP_BAR_GLOSS)
        love.graphics.rectangle("fill", innerLeft + rounding, innerTop, innerWidth * front - rounding * 2, Units.LINE)
    end

    UI.Theme.setColor(Palette.hp.border, 0.9)
    love.graphics.rectangle("line", left, top, width, HP_BAR_HEIGHT, HP_BAR_ROUNDING)
    love.graphics.setColor(1, 1, 1, 1)
end

return Entity