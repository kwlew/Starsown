--- Shared base for anything that lives in the world: a body, health, and the
-- knockback and hit flash both the player and the enemies react with.
--
-- x, y is where a body stands. Height is a third axis on top of that: z rises,
-- gravity brings it back, and nothing about the gameplay reads z at all --
-- collision, aim and hit tests all stay on the ground plane. It only changes
-- where the body is painted and how its shadow looks (see game/perspective.lua).
--
--   ---@class Slime : Entity
--   local Slime = Entity.extend()
--   function Slime.new(x, y)
--       return Entity.init(setmetatable({}, Slime), { x = x, y = y, sides = 3 })
--   end
--
-- The annotation isn't decoration: extend() hands back an anonymous table, so
-- without it the language server can't tell a subclass from Entity itself and
-- reads every override as a duplicate field (and resolves calls against the
-- base's signature).

local Theme = require "ui.core.theme"
local Math = require "utils.math"
local Palette = require "game.palette"
local Shape = require "game.shape"
local Perspective = require "game.perspective"

---@class Entity
---@field x number
---@field y number
---@field radius number
---@field sides integer|nil nil or < 3 draws a circle
---@field color number[]
---@field hp number
---@field maxHp number
---@field facing number
---@field vx number
---@field vy number
---@field z number height above the ground; see game/perspective.lua
---@field vz number
---@field kx number knockback, decays on its own
---@field ky number
---@field flash number
---@field stagger number
---@field dead boolean
local Entity = {}
Entity.__index = Entity

local GRAVITY = 900 -- world units/sec^2; only ever runs while something is airborne
local KNOCKBACK_DRAG = 9
local HIT_FLASH_TIME = 0.14
local STAGGER_TIME = 0.12
local OUTLINE_WIDTH = 2

--- see the note above: annotate the result with ---@class Sub : Entity, or the
-- language server reads every override as a duplicate field
---@return table class
function Entity.extend()
    local class = setmetatable({}, { __index = Entity })
    class.__index = class
    return class
end

--- fills in an already-constructed table, so a subclass can setmetatable first
-- and pass it straight in
---@param self table
---@param config table # { x?: number, y?: number, radius?: number, sides?: integer, color?: number[], hp?: number, facing?: number, z?: number }
---@return table self
function Entity.init(self, config)
    self.x = config.x or 0
    self.y = config.y or 0
    self.radius = config.radius or 12
    self.sides = config.sides -- nil or < 3 draws a circle
    self.color = config.color or Palette.outline
    self.hp = config.hp or 1
    self.maxHp = self.hp
    self.facing = config.facing or 0
    self.vx, self.vy = 0, 0
    self.z = config.z or 0 -- height above the ground
    self.vz = 0
    self.kx, self.ky = 0, 0 -- knockback, decays on its own
    self.flash = 0
    self.stagger = 0
    self.dead = false
    return self
end

---@param config? table
---@return Entity
function Entity.new(config)
    return Entity.init(setmetatable({}, Entity), config or {})
end

--- hurts it, flashes it, staggers it and shoves it. Already-dead bodies take
-- nothing, so two hits landing the same frame can't kill twice.
---@param amount number
---@param knockX? number
---@param knockY? number
---@param knockZ? number # upward, so a hit can pop a body off the ground
---@return boolean # landed false if it was already dead
function Entity:damage(amount, knockX, knockY, knockZ)
    if self.dead then return false end
    self.hp = self.hp - amount
    self.flash = HIT_FLASH_TIME
    self.stagger = STAGGER_TIME
    self.kx = self.kx + (knockX or 0)
    self.ky = self.ky + (knockY or 0)
    self.vz = self.vz + (knockZ or 0)
    if self.hp <= 0 then self.dead = true end
    return true
end

--- decays the flash, stagger and knockback, and runs gravity while airborne
---@param dt number
function Entity:update(dt)
    self.flash = math.max(0, self.flash - dt)
    self.stagger = math.max(0, self.stagger - dt)
    local decay = Math.decay(KNOCKBACK_DRAG, dt)
    self.kx, self.ky = self.kx * decay, self.ky * decay

    if self.z > 0 or self.vz ~= 0 then
        self.vz = self.vz - GRAVITY * dt
        self.z = self.z + self.vz * dt
        if self.z <= 0 then self.z, self.vz = 0, 0 end
    end
end

---@return boolean
function Entity:airborne()
    return self.z > 0
end

--- nothing on the ground blocks anything yet, so this is a plain integrate; it
-- stays a method so obstacles only ever have to change one place
---@param dx number
---@param dy number
function Entity:moveBy(dx, dy)
    self.x = self.x + dx
    self.y = self.y + dy
end

---@param other table # anything with x, y
---@return number distance
---@return number # dx toward the other body
---@return number # dy toward the other body
function Entity:distanceTo(other)
    local dx, dy = other.x - self.x, other.y - self.y
    return Math.length(dx, dy), dx, dy
end

--- where the body is painted: above its own feet, and higher again with height
---@return number
function Entity:drawY()
    return self.y - self.radius * Perspective.STAND - Perspective.lift(self.z)
end

--- the mark on the ground, drawn before any body so a nearer entity's shadow
-- can't land on top of a farther entity
function Entity:drawGround()
    local fade = Perspective.shadowFade(self.z)
    local radius = self.radius * Perspective.SHADOW_SPREAD * fade

    love.graphics.setColor(Palette.shadow[1], Palette.shadow[2], Palette.shadow[3],
        Perspective.SHADOW_ALPHA * fade)
    love.graphics.ellipse("fill", self.x, self.y, radius, radius * Perspective.SHADOW_SQUASH)
end

---@return number r
---@return number g
---@return number b
function Entity:bodyColor()
    local body = self.color
    if self.flash <= 0 then return body[1], body[2], body[3] end
    return Theme.lerp(body, Palette.flash, self.flash / HIT_FLASH_TIME)
end

--- the filled body and its outline; call drawGround() for every entity first
function Entity:draw()
    local r, g, b = self:bodyColor()
    local y = self:drawY()
    local radius = self.radius * Perspective.scale(self.z)

    love.graphics.setColor(r, g, b)
    Shape.draw("fill", self.x, y, radius, self.sides, self.facing)

    love.graphics.setLineWidth(OUTLINE_WIDTH)
    Theme.setColor(Palette.outline, 0.55)
    Shape.draw("line", self.x, y, radius, self.sides, self.facing)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

return Entity
