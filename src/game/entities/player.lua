--- The player: walks with keys, swings at the cursor.

local Controls = require("game.input.controls")
local Entity = require("game.entity")
local HitEffect = require("game.effects.hit")
local Stamina = require("game.components.stamina")
local Swipe = require("game.swipe")
local UI = require("ui")

local SPRINT_MULTIPLIER = 1.15

local Player = Entity:extend{
    name = "player",
    kind = "player",
    mass = 4, -- crowds barely shove it
    facesMovement = false, -- faces the cursor
    maxSpeed = 115,
    maxHealth = 10,
    maxStamina = 100,
    invulnerableTime = 0.6,
    texture = "assets/textures/game/player.png",
    fallbackColor = "text",
}

function Player:init()
    self.stamina = Stamina.new(self.maxStamina)
    self.swipe = Swipe.new{ damage = 2, knockback = 300 }
end

---@return number # radians toward the cursor
function Player:aimFrom(x, y)
    if not self.aimX or (self.aimX == x and self.aimY == y) then return self.angle end
    return math.atan2(self.aimY - y, self.aimX - x)
end

--- aim follows the cursor live, never a tick behind
function Player:drawAngle(x, y)
    return self:aimFrom(x, y)
end

--- aims and swings from the drawn position
function Player:frame(dt, world, alpha)
    self.aimX, self.aimY = world.camera:toWorld(love.mouse.getPosition())
    local x, y = self:lerpPosition(alpha)
    if Controls.attacking() then self.swipe:swing(self:aimFrom(x, y)) end
    self.swipe:update(dt, x, y, world, self, alpha)
end

function Player:think(dt)
    local ix, iy = Controls.move()
    self:setMove(ix, iy)
    local sprinting = Controls.sprinting() and (ix ~= 0 or iy ~= 0) and self.stamina:canSprint()
    self.stamina:update(dt, sprinting)
    self.speed = self.maxSpeed * (sprinting and SPRINT_MULTIPLIER or 1)
    self.angle = self:aimFrom(self.x, self.y)
end

--- a flash on the side it came from, chunks thrown away from it
function Player:hurt(amount, source)
    if not self.world then return end
    local x, y = self.drawnX or self.x, self.drawnY or self.y
    local angle = source and math.atan2(y - source.y, x - source.x) or self.angle + math.pi
    local edge = self.radius * 0.6
    self.world:addEffect(HitEffect.new(
        x - math.cos(angle) * edge, y - math.sin(angle) * edge, angle, UI.Theme.colors.danger))
end

function Player:drawEffects()
    self.swipe:draw()
end

return Player
