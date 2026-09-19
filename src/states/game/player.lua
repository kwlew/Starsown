---@diagnostic disable: duplicate-set-field
-- src/states/game/player.lua
-- Player module.

local Entity = require "states.game.kernel.entity"
local World = require "states.game.rendering.world"
local Palette = require "states.game.rendering.palette"
local Perspective = require "states.game.rendering.perspective"
local Math = require "utils.math"

local Player = Entity.extend()

Player.RADIUS = World.TILE / 2
Player.RANGE = World.TILE * 3

local SPEED = 140
local ACCEL = 12
local FACING_GRACE = math.rad(50) -- wider than 45 so a diagonal off a cardinal aim still counts as forward
local OFF_FACING_SPEED = 0.55 -- speed/accel multipliers when moving directly away from facing
local OFF_FACING_ACCEL = 0.5
local SPRINT_SPEED = 1.2
local STAMINA_MAX = 100
local SPRINT_DRAIN = 10 -- per second
local STAMINA_REGEN = 4 -- per second
local REGEN_DELAY = 0.8 -- seconds after sprinting before it refills
local EXHAUST_RECOVER = 25 -- once drained to 0, no sprinting again until it refills this far
local SPRINT_BLEND_RATE = 5 -- how quickly the sprint speed boost fades in and out
local STAMINA_FRONT_RATE = 14
local STAMINA_TRAIL_RATE = 5
local STAMINA_TRAIL_DELAY = 0.45
local EXHAUST_FADE_RATE = 8
local NUB_INNER = 0.55
local NUB_WIDTH = 7
local GLOW_SPREAD = 6
local GLOW_ALPHA = 0.10
local GLOW_LAYERS = 3

local RANGE_FADE = 12
local RANGE_ALPHA = 0.34
local RANGE_SEGMENTS = 64

local BINDINGS = {
    w = "up", up = "up",
    s = "down", down = "down",
    a = "left", left = "left",
    d = "right", right = "right",
    lshift = "sprint", rshift = "sprint",
}


--- Initialize a new player.
---@param x number
---@param y number
---@return table
function Player.new(x, y)
    local self = Entity.init(setmetatable({}, Player), {
        hp = 100, maxHp = 100,
        x = x, y = y,
        radius = Player.RADIUS,
        color = Palette.entity.Player.color,
        sides = 32
    })
    self.stamina = 100
    self.maxStamina = 100
    self.held = {}
    self.attacking = false
    self.aimX, self.aimY = x + Player.RANGE, y
    self.aimPinned = false
    self.rangeGlow = 0
    self.maxStamina = STAMINA_MAX
    self.stamina = STAMINA_MAX
    self.staminaDelay = 0
    self.exhausted = false
    self.sprinting = false
    self.sprintBlend = 0
    self.staminaFront, self.staminaTrail, self.staminaTrailDelay = STAMINA_MAX, STAMINA_MAX, 0
    self.exhaustFade = 0

    return self
end

function Player:sprint()
    if self.stamina > 0 then
        self.stamina = math.max(0, self.stamina - 30 * love.timer.getDelta())
        return true
    else
        return false
    end
end

--- Release ongoing actions and reset the player's state.
function Player:releaseAll()
    for action in pairs(self.held) do self.held[action] = nil end
    self.attacking = false
end

--- Handle key press events for the player.
--- @param key string
function Player:keypressed(key)
    local action = BINDINGS[key]
    if action then self.held[action] = true end
end

function Player:keyreleased(key)
    local action = BINDINGS[key]
    if action then self.held[action] = nil end
end

--- Set the player's attacking state.
--- @param attacking boolean
function Player:selfAttacking(attacking)
    self.attacking = attacking
end


--- Set the player's aiming position.
--- @param x number
--- @param y number
function Player:aimAt(x, y)
    local dx, dy = x - self.x, y - self.y
    local distance = Math.length(dx, dy)

    self.aimPinned = distance > Player.RANGE
    if self.aimPinned then
        local scale = Player.RANGE / distance
        dx, dy = dx * scale, dy * scale
    end

    self.aimX, self.aimY = self.x + dx, self.y + dy
    if distance > 0 then self.facing = math.atan2(dy, dx) end
end

--- Sprinting drains stamina; it refills after a short pause. Emptying it
-- locks sprint out until it has recovered a bit, so holding shift can't
-- stutter at 0.
---@param dt number
---@param moving boolean
function Player:updateStamina(dt, moving)
    self.sprinting = self.held.sprint == true and moving and not self.exhausted and self.stamina > 0

    if self.sprinting then
        self.stamina = math.max(0, self.stamina - SPRINT_DRAIN * dt)
        self.staminaDelay = REGEN_DELAY
        self.staminaTrailDelay = STAMINA_TRAIL_DELAY
        if self.stamina == 0 then self.exhausted = true end
    else
        self.staminaDelay = math.max(0, self.staminaDelay - dt)
        if self.staminaDelay == 0 then
            self.stamina = math.min(self.maxStamina, self.stamina + STAMINA_REGEN * dt)
        end
        if self.exhausted and self.stamina >= EXHAUST_RECOVER then self.exhausted = false end
    end

    -- display-only easing, same shape as Entity's hp front/trail
    self.staminaFront = Math.damp(self.staminaFront, self.stamina, STAMINA_FRONT_RATE, dt)
    self.staminaTrailDelay = math.max(0, self.staminaTrailDelay - dt)
    if self.staminaTrail < self.staminaFront then
        self.staminaTrail = self.staminaFront
    elseif self.staminaTrailDelay == 0 then
        self.staminaTrail = Math.damp(self.staminaTrail, self.staminaFront, STAMINA_TRAIL_RATE, dt)
    end

    self.sprintBlend = Math.damp(self.sprintBlend, self.sprinting and 1 or 0, SPRINT_BLEND_RATE, dt)
    self.exhaustFade = Math.damp(self.exhaustFade, self.exhausted and 1 or 0, EXHAUST_FADE_RATE, dt)
end

--- Update the player on dt.
---@param dt number
---@param ctx any
function Player:update(dt, ctx)
    Entity.update(self, dt)

    if ctx then self:aimAt(ctx.pointerX, ctx.pointerY) end

    local dx, dy = self:moveInput()
    local forward = self:forwardness(dx, dy)
    self:updateStamina(dt, dx ~= 0 or dy ~= 0)
    local speed = SPEED * (OFF_FACING_SPEED + (1 - OFF_FACING_SPEED) * forward)
    speed = speed * (1 + (SPRINT_SPEED - 1) * self.sprintBlend)
    local accel = ACCEL * (OFF_FACING_ACCEL + (1 - OFF_FACING_ACCEL) * forward)
    self.vx = Math.damp(self.vx, dx * speed, accel, dt)
    self.vy = Math.damp(self.vy, dy * speed, accel, dt)

    self:moveby((self.vx + self.kx) * dt, (self.vy + self.ky) * dt)
    self.rangeGlow = Math.damp(self.rangeGlow, self.aimPinned and 1 or 0, RANGE_FADE, dt)
end

--- 1 while (dx, dy) is within the grace cone of where the player faces, easing
-- down to 0 as it swings to directly behind. No input counts as forward, so
-- stopping isn't slowed.
---@param dx number
---@param dy number
---@return number
function Player:forwardness(dx, dy)
    if dx == 0 and dy == 0 then return 1 end
    local off = math.abs((math.atan2(dy, dx) - self.facing + math.pi) % (math.pi * 2) - math.pi)
    if off <= FACING_GRACE then return 1 end
    local t = Math.clamp01((off - FACING_GRACE) / (math.pi - FACING_GRACE))
    return 1 - t * t * (3 - 2 * t)
end

--- Held-key direction, normalized so diagonals aren't faster.
---@return number dx
---@return number dy
function Player:moveInput()
    local dx = (self.held.right and 1 or 0) - (self.held.left and 1 or 0)
    local dy = (self.held.down and 1 or 0) - (self.held.up and 1 or 0)
    if dx ~= 0 and dy ~= 0 then
        local inv = 1 / math.sqrt(2)
        dx, dy = dx * inv, dy * inv
    end
    return dx, dy
end

---@return number Speed
function Player:speed()
    return Math.length(self.vx, self.vy)
end

--- Draw the player on the screen.
function Player:drawGround()
    Entity.drawGround(self)
    if self.rangeGlow <= 0.01 then return end

    love.graphics.setColor(Palette.range[1], Palette.range[2], Palette.range[3],
        RANGE_ALPHA * self.rangeGlow)
    love.graphics.circle("line", self.x, self.y, Player.RANGE, RANGE_SEGMENTS)
end

--- Draw the player on the screen.
function Player:draw()
    local y = self:drawY()
    local radius = self.radius * Perspective.scale(self.z)

    local glow = Palette.entity.Player.color
    love.graphics.setBlendMode("add")
    for i = GLOW_LAYERS, 1, -1 do
        love.graphics.setColor(glow[1], glow[2], glow[3], GLOW_ALPHA / i)
        love.graphics.circle("fill", self.x, y, radius + i * GLOW_SPREAD)
    end
    love.graphics.setBlendMode("alpha")

    Entity.draw(self)

    love.graphics.setColor(Palette.entity.Player.color)
    love.graphics.setLineWidth(NUB_WIDTH)
    local innerX, innerY = Math.polar(self.x, y, self.facing, radius * NUB_INNER)
    local outerX, outerY = Math.polar(self.x, y, self.facing, radius)
    love.graphics.line(innerX, innerY, outerX, outerY)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

return Player