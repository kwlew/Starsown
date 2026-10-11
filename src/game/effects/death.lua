--- A dead entity's last pose fading out, breaking into chunks of its own
-- colours, with a puff of smoke unless it opts out.

local Particles = require("particles")
local Textures = require("game.textures")
local Tile = require("game.tile")

local DeathEffect = {}
DeathEffect.__index = DeathEffect

local INHERIT = 0.3 -- of its motion carried into the debris
local SMOKE_COLOR = { 0.85, 0.85, 0.82 }

local CHUNKS = {
    countMin = 8, countMax = 12,
    sizeMin = 1.5, sizeMax = 3.5, -- one or two texels
    speedMin = 70, speedMax = 260,
    lifeMin = 0.4, lifeMax = 0.8,
    drag = 4,
    fade = 0.35,
    hot = 0.25, -- a white blink, so dark art reads on grass
    spin = 10,
    additive = false,
    texture = "square",
}
local SMOKE = {
    countMin = 4, countMax = 6,
    sizeMin = 3, sizeMax = 5,
    speedMin = 10, speedMax = 40,
    lifeMin = 0.35, lifeMax = 0.6,
    drag = 3,
    grow = 1.5,
    alpha = 0.5,
    additive = false,
    texture = "puff",
}

---@param entity table
---@return number[][]
local function colorsOf(entity)
    local colors = entity.texture and not entity.tint and Textures.palette(entity.texture)
    if colors and #colors > 0 then return colors end
    return { entity:color() }
end

---@param entity table # already dead; read for its look
---@return table
function DeathEffect.new(entity)
    local self = setmetatable({
        entity = entity,
        -- last drawn pose: the tick position can be a tick ahead of it
        x = entity.drawnX or entity.x, y = entity.drawnY or entity.y,
        angle = entity.drawnAngle or entity.angle,
        fade = entity.deathFade,
        t = 0,
        smoke = Particles.Burst.new(SMOKE),
        chunks = Particles.Burst.new(CHUNKS),
    }, DeathEffect)
    local x, y, scale = self.x, self.y, entity.deathScale
    local vx, vy = entity.vx * INHERIT, entity.vy * INHERIT
    if entity.deathSmoke then self.smoke:spawn(x, y, SMOKE_COLOR, scale, vx, vy) end
    self.chunks:spawnMixed(x, y, colorsOf(entity), scale, vx, vy)
    return self
end

---@return boolean
function DeathEffect:done()
    return self.t >= self.fade and #self.smoke.particles == 0
        and #self.chunks.particles == 0
end

---@param dt number
function DeathEffect:update(dt)
    self.t = self.t + dt
    self.smoke:update(dt)
    self.chunks:update(dt)
end

function DeathEffect:draw()
    if self.t < self.fade then self.entity:drawBody(self.x, self.y, self.angle, 1 - self.t / self.fade) end
    love.graphics.push("all")
    love.graphics.scale(Tile.worldScale())
    self.smoke:draw()
    self.chunks:draw()
    love.graphics.pop()
end

return DeathEffect
