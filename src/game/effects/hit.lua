--- A hit landing on something: a pixel flash, chunks knocked away.

local Effect = require("game.effects.effect")
local Particles = require("particles")
local Shapes = require("particles.shapes")
local Tile = require("game.tile")

local HitEffect = Effect.extend{}

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
    texture = "debris",
}

---@param x number # design px, where it landed
---@param y number
---@param angle number # radians the chunks fly toward
---@param color number[] # RGB
---@return table
function HitEffect.new(x, y, angle, color)
    local chunks = Particles.Burst.new(CHUNKS)
    local self = Effect.init(setmetatable({ x = x, y = y, color = color }, HitEffect), { chunks }, FLASH_LIFE)
    chunks:spawnCone(x, y, angle, SPREAD, color)
    return self
end

--- a pixel star, white and doubled, then one size in `color`, fading:
-- whole texels throughout. Inside a world-scaled transform.
---@param k number # 0..1 through it
---@param color number[] # RGB
function HitEffect.star(x, y, k, color)
    local image = Shapes.get("hit_star")
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

function HitEffect:drawOver()
    if self.t < self.life then HitEffect.star(self.x, self.y, self.t / self.life, self.color) end
end

return HitEffect
