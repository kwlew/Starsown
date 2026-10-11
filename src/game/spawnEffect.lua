--- The player arriving: glitter rising from a ring around it, outside the
-- body so a bright sprite doesn't swallow it.

local Math = require("utils.math")
local Particles = require("particles")
local Tile = require("game.tile")
local UI = require("ui")

local SpawnEffect = {}
SpawnEffect.__index = SpawnEffect

local RING = 1.3 -- of the body's radius
local COUNT = 28

local GLITTER = {
    sizeMin = 0.8, sizeMax = 1.8,
    speedMin = 15, speedMax = 50,
    lifeMin = 0.7, lifeMax = 1.3,
    drag = 2,
    gravity = -50, -- rises
    hot = 0.3,
    glow = 3,
    twinkle = 0.8,
}

---@param radius number # the body's, design px
---@return table
function SpawnEffect.new(x, y, radius)
    local self = setmetatable({ glitter = Particles.Burst.new(GLITTER) }, SpawnEffect)
    local color = UI.Theme.colors.highlight
    for i = 1, COUNT do
        local angle = (i + math.random()) / COUNT * math.pi * 2
        local px, py = Math.polar(x, y, angle, radius * RING)
        self.glitter:emit(px, py, angle, color, 1)
    end
    return self
end

---@return boolean
function SpawnEffect:done()
    return #self.glitter.particles == 0
end

---@param dt number
function SpawnEffect:update(dt)
    self.glitter:update(dt)
end

function SpawnEffect:draw()
    love.graphics.push("all")
    love.graphics.scale(Tile.worldScale())
    self.glitter:draw()
    love.graphics.pop()
end

return SpawnEffect
