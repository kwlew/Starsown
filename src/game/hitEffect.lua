--- A hit landing on something: a pixel flash, chunks knocked away.

local Particles = require("particles")
local ParticleTextures = require("particles.textures")
local Tile = require("game.tile")

local HitEffect = {}
HitEffect.__index = HitEffect

local FLASH_LIFE = 0.16
local FLASH_BIG = 0.35 -- of its life drawn at double size
local SPREAD = math.pi * 0.9

local CHUNKS = {
    countMin = 8, countMax = 12,
    sizeMin = 1.5, sizeMax = 3, -- about one texel
    speedMin = 70, speedMax = 200,
    lifeMin = 0.25, lifeMax = 0.5,
    drag = 6,
    fade = 0.4,
    hot = 0.3,
    spin = 12,
    additive = false, -- matter, not light
    texture = "square",
}

---@param x number # design px, where it landed
---@param y number
---@param angle number # radians the chunks fly toward
---@param color number[] # RGB
---@return table
function HitEffect.new(x, y, angle, color)
    local self = setmetatable({
        x = x, y = y, color = color, t = 0,
        chunks = Particles.Burst.new(CHUNKS),
    }, HitEffect)
    self.chunks:spawnCone(x, y, angle, SPREAD, color)
    return self
end

---@return boolean
function HitEffect:done()
    return self.t >= FLASH_LIFE and #self.chunks.particles == 0
end

---@param dt number
function HitEffect:update(dt)
    self.t = self.t + dt
    self.chunks:update(dt)
end

--- a pixel star, white and doubled, then one size in `color`, fading:
-- whole texels throughout. Inside a world-scaled transform.
---@param k number # 0..1 through it
---@param color number[] # RGB
function HitEffect.star(x, y, k, color)
    local image = ParticleTextures.hitStar()
    local w, h = image:getDimensions()
    local texel = Tile.SIZE / Tile.ART
    if k < FLASH_BIG then
        love.graphics.setColor(1, 1, 1, 1)
        texel = texel * 2
    else
        love.graphics.setColor(color[1], color[2], color[3], 1 - (k - FLASH_BIG) / (1 - FLASH_BIG))
    end
    love.graphics.draw(image, x, y, 0, texel, texel, w / 2, h / 2)
end

function HitEffect:draw()
    love.graphics.push("all")
    love.graphics.scale(Tile.worldScale())
    self.chunks:draw()
    if self.t < FLASH_LIFE then HitEffect.star(self.x, self.y, self.t / FLASH_LIFE, self.color) end
    love.graphics.pop()
end

return HitEffect
