--- Throws bones from mid range; walks up and hits otherwise.
-- A throw: stand still facing the player, then release.

local Bone = require("game.entities.bone")
local Hostile = require("game.entities.hostile")
local Math = require("utils.math")
local ParticleTextures = require("particles.textures")
local Textures = require("game.textures")
local Tile = require("game.tile")
local UI = require("ui")

local HOLD_OFFSET = 14 -- design px in front while winding up
local GLINT_FROM = 0.4 -- of the windup before the bone glints
local GLINT_WHITE = 0.8 -- then flashes white just before release

local Skeleton = Hostile:extend{
    name = "skeleton",
    maxSpeed = 90,
    maxHealth = 5,
    aggroRange = 340,
    attackCooldown = 0.8,
    throwMinRange = 120, -- closer than this, melee instead
    throwRange = 300,    -- farther than this, walk closer
    throwWindup = 0.30,
    throwCooldown = 0.50,
    texture = "assets/textures/game/skeleton.png",
}

function Skeleton:init(opts)
    ---@diagnostic disable-next-line: redundant-parameter
    Hostile.init(self, opts)
    self.throwTimer = 0.6 + math.random() * 0.8 -- groups don't throw together
    self.windup = nil
end

function Skeleton:think(dt, world)
    self.throwTimer = math.max(0, self.throwTimer - dt)
    Hostile.think(self, dt, world)
    if not self.target then self.windup = nil end
end

---@param target table
---@return boolean
function Skeleton:inThrowBand(target)
    local distance = self:distanceTo(target)
    return distance >= self.throwMinRange and distance <= self.throwRange
end

function Skeleton:engage(target, dt, world)
    if self.windup then
        self.windup = self.windup - dt
        self:faceStill(target)
        if self.windup <= 0 then
            self:throw(target, world)
            self.windup, self.throwTimer = nil, self.throwCooldown
        end
        return
    end
    if self.throwTimer == 0 and self:inThrowBand(target) then
        self.windup = self.throwWindup
        return self:faceStill(target)
    end
    Hostile.engage(self, target, dt, world)
end

--- stops walking but keeps facing `target`
---@param target table
function Skeleton:faceStill(target)
    self:setMove(target.x - self.x, target.y - self.y)
    self.speed = 0
    self.goalX, self.goalY, self.state = target.x, target.y, "windup"
end

--- aims where the player is now; no homing
function Skeleton:throw(target, world)
    local angle = math.atan2(target.y - self.y, target.x - self.x)
    local x, y = Math.polar(self.x, self.y, angle, HOLD_OFFSET)
    world:spawn(Bone, x, y, { angle = angle, owner = self, range = self.throwRange * 1.4 })
end

--- a star brightening on the held bone: the throw's tell
---@param k number # 0..1 through the windup
local function drawGlint(x, y, k, scale)
    if k < GLINT_FROM then return end
    local image = ParticleTextures.hitStar()
    local w, h = image:getDimensions()
    if k >= GLINT_WHITE then
        love.graphics.setColor(1, 1, 1, 1)
    else
        UI.Theme.setColor(UI.Theme.colors.highlight, (k - GLINT_FROM) / (GLINT_WHITE - GLINT_FROM))
    end
    love.graphics.setBlendMode("add")
    love.graphics.draw(image, x, y, 0, scale, scale, w / 2, h / 2)
    love.graphics.setBlendMode("alpha")
end

--- the bone held out during the windup
---@param alpha number
function Skeleton:drawEffects(alpha)
    local image = self.windup and Textures.get(Bone.texture)
    if not image then return end
    local x, y = self:lerpPosition(alpha)
    local a = self:drawAngle(x, y, alpha)
    local hx, hy = Math.polar(x, y, a, HOLD_OFFSET)
    local s, scale = Tile.worldScale(), Tile.pixelScale()
    local w, h = image:getDimensions()
    local bx, by = Math.round(hx * s), Math.round(hy * s)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, bx, by, a, scale, scale, w / 2, h / 2)
    drawGlint(bx, by, 1 - self.windup / self.throwWindup, scale)
    love.graphics.setColor(1, 1, 1, 1)
end

return Skeleton
