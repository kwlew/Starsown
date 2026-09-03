--- The player: a circle exactly one tile across, walked with WASD and swinging
-- at whatever the cursor points at. The cursor is tethered inside RANGE of
-- them (Darkwood does this): push the pointer further and the aim keeps the
-- angle but stops at the ring, which is the reach everything else is measured
-- against. states/play.lua draws the real cursor at that clamped point and
-- warps the hardware pointer there too (Play:tetherPointer), so the OS
-- pointer can't drift away from the aim it's supposed to be driving.

local Entity = require "game.entity"
local World = require "game.world"
local Swipe = require "game.swipe"
local Palette = require "game.palette"
local Perspective = require "game.perspective"
local Math = require "utils.math"

---@class Player : Entity
---@field id string
---@field held table<string, boolean>
---@field attacking boolean
---@field aimX number
---@field aimY number
---@field aimPinned boolean true while the pointer is pushing against the ring
---@field rangeGlow number
---@field swipe table
local Player = Entity.extend()

Player.RADIUS = World.TILE / 2 -- "the size of a block", so this follows the tile
Player.RANGE = World.TILE * 4  -- how far out the cursor may be pushed
Player.MAX_HP = 10             -- no death handling yet -- see Player:damage
local SPEED = 200              -- world units/sec, a bit over six tiles
local ACCEL = 16               -- exponential approach toward the target velocity
local NUB_INNER = 0.55         -- fraction of the radius the facing tick starts at
local NUB_WIDTH = 3
local GLOW_SPREAD = 6
local GLOW_ALPHA = 0.10
local GLOW_LAYERS = 3
local RANGE_FADE = 12
local RANGE_ALPHA = 0.34
local RANGE_SEGMENTS = 64
local ENEMY_YIELD = 0.15

local BINDINGS = {
    w = "up",    up = "up",
    s = "down",  down = "down",
    a = "left",  left = "left",
    d = "right", right = "right",
}

---@param x number
---@param y number
---@return Player
function Player.new(x, y)
    local self = Entity.init(setmetatable({}, Player), {
        x = x, y = y,
        radius = Player.RADIUS,
        color = Palette.player,
        hp = Player.MAX_HP,
    })
    ---@cast self Player
    self.id = "player"
    self.held = {}
    self.attacking = false
    self.aimX, self.aimY = x + Player.RANGE, y
    self.aimPinned = false
    self.rangeGlow = 0
    self.swipe = Swipe.new{}
    return self
end

--- overrides Entity:damage: no death handling yet, so hp stays free to go
-- negative rather than freezing the moment it first crosses zero -- Entity's
-- own dead-gate would otherwise swallow every hit after the first kill-shot.
-- Delete the reset below once there's an actual death to trigger.
---@param amount number
---@param knockX? number
---@param knockY? number
---@param knockZ? number
function Player:damage(amount, knockX, knockY, knockZ)
    Entity.damage(self, amount, knockX, knockY, knockZ)
    self.dead = false
end

--- held is event-driven (see the note in core/stateManager.lua on why
-- keyreleased is never swallowed); a screen change still clears it, since a key
-- let go on another screen would otherwise stay down forever
function Player:releaseAll()
    for action in pairs(self.held) do self.held[action] = nil end
    self.attacking = false
end

---@param key string # non-movement keys are ignored
function Player:keypressed(key)
    local action = BINDINGS[key]
    if action then self.held[action] = true end
end

---@param key string
function Player:keyreleased(key)
    local action = BINDINGS[key]
    if action then self.held[action] = nil end
end

---@return number # dx; -1..1, normalized so diagonals aren't faster
---@return number # dy; -1..1
function Player:moveInput()
    local dx = (self.held.right and 1 or 0) - (self.held.left and 1 or 0)
    local dy = (self.held.down and 1 or 0) - (self.held.up and 1 or 0)
    if dx ~= 0 and dy ~= 0 then
        local inverse = 1 / math.sqrt(2) -- or a diagonal outruns the axes
        dx, dy = dx * inverse, dy * inverse
    end
    return dx, dy
end

--- held down, not tapped: update() keeps asking for a swing and the swipe's own
-- cooldown is what paces them, so holding the button chains attacks
---@param attacking boolean
function Player:setAttacking(attacking)
    self.attacking = attacking
end

--- Pulls the aim toward a world point but no further out than RANGE. Only the
-- distance is capped: the angle always tracks the pointer exactly, so aiming
-- still works with the pointer parked well outside the ring.
---@param x number # world point the pointer is over
---@param y number
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

--- a direct position correction rather than a velocity push (like
-- Enemy:separate): vx/vy here is the player's own damped input velocity,
-- not something safe to nudge for one frame and let the next frame's damp
-- forget about. Split unevenly rather than shared 50/50, so walking into an
-- enemy reads as the player bumping something solid, with the enemy only
-- giving a little ground, rather than the two of them meeting in the middle.
---@param enemies Enemy[]
function Player:collideWithEnemies(enemies)
    for _, enemy in ipairs(enemies) do
        if not enemy.dead then
            local distance, dx, dy = self:distanceTo(enemy)
            local reach = self.radius + enemy.radius
            if distance > 0.001 and distance < reach then
                local overlap = reach - distance
                local nx, ny = dx / distance, dy / distance
                self.x = self.x - nx * overlap * (1 - ENEMY_YIELD)
                self.y = self.y - ny * overlap * (1 - ENEMY_YIELD)
                enemy.x = enemy.x + nx * overlap * ENEMY_YIELD
                enemy.y = enemy.y + ny * overlap * ENEMY_YIELD
            end
        end
    end
end

--- movement, collision, aim, and the swing the attack button is asking for
---@param dt number
---@param ctx table # reads ctx.enemies, ctx.pointerX/pointerY and ctx.enemyManager
function Player:update(dt, ctx)
    Entity.update(self, dt)

    local dx, dy = self:moveInput()
    self.vx = Math.damp(self.vx, dx * SPEED, ACCEL, dt)
    self.vy = Math.damp(self.vy, dy * SPEED, ACCEL, dt)
    self:moveBy((self.vx + self.kx) * dt, (self.vy + self.ky) * dt)
    self:collideWithEnemies(ctx.enemies)

    self:aimAt(ctx.pointerX, ctx.pointerY)
    self.rangeGlow = Math.damp(self.rangeGlow, self.aimPinned and 1 or 0, RANGE_FADE, dt)

    if self.attacking then self.swipe:swing(self.facing) end
    self.swipe:update(dt, self, ctx.enemyManager)
end

---@return number # world units per second
function Player:speed()
    return Math.length(self.vx, self.vy)
end

--- the reach ring is painted on the ground, not on the player, so it belongs
-- with the shadow rather than with the body that floats above it
function Player:drawGround()
    Entity.drawGround(self)
    if self.rangeGlow <= 0.01 then return end

    love.graphics.setColor(Palette.range[1], Palette.range[2], Palette.range[3],
        RANGE_ALPHA * self.rangeGlow)
    love.graphics.circle("line", self.x, self.y, Player.RANGE, RANGE_SEGMENTS)
end

--- an additive bloom under the body, and a tick marking which way it faces
function Player:draw()
    local y = self:drawY()
    local radius = self.radius * Perspective.scale(self.z)

    local glow = Palette.player
    love.graphics.setBlendMode("add")
    for i = GLOW_LAYERS, 1, -1 do
        love.graphics.setColor(glow[1], glow[2], glow[3], GLOW_ALPHA / i)
        love.graphics.circle("fill", self.x, y, radius + i * GLOW_SPREAD)
    end
    love.graphics.setBlendMode("alpha")

    Entity.draw(self)

    love.graphics.setColor(Palette.blade)
    love.graphics.setLineWidth(NUB_WIDTH)
    local innerX, innerY = Math.polar(self.x, y, self.facing, radius * NUB_INNER)
    local outerX, outerY = Math.polar(self.x, y, self.facing, radius)
    love.graphics.line(innerX, innerY, outerX, outerY)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

return Player
