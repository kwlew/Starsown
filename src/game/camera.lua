-- Follows a target around the world. Everything drawn between attach() and
-- detach() is in world coordinates; toWorld/toScreen convert across the seam.
-- The world is open, so there is nothing to clamp the view against.

local Math = require "utils.math"

local Camera = {}
Camera.__index = Camera

local FOLLOW_SPEED = 9 -- exponential approach per second, not per frame

function Camera.new(config)
    config = config or {}
    return setmetatable({
        x = config.x or 0, -- the world point sitting at the centre of the screen
        y = config.y or 0,
        zoom = config.zoom or 1,
    }, Camera)
end

function Camera:snapTo(x, y)
    self.x, self.y = x, y
end

function Camera:follow(x, y, dt)
    self.x = Math.damp(self.x, x, FOLLOW_SPEED, dt)
    self.y = Math.damp(self.y, y, FOLLOW_SPEED, dt)
end

-- half the view, in world units
function Camera:halfExtents()
    local w, h = love.graphics.getDimensions()
    return w / (2 * self.zoom), h / (2 * self.zoom)
end

function Camera:attach()
    local w, h = love.graphics.getDimensions()
    love.graphics.push()
    love.graphics.translate(w / 2, h / 2)
    love.graphics.scale(self.zoom)
    love.graphics.translate(-self.x, -self.y)
end

function Camera:detach()
    love.graphics.pop()
end

function Camera:toWorld(screenX, screenY)
    local w, h = love.graphics.getDimensions()
    return (screenX - w / 2) / self.zoom + self.x,
           (screenY - h / 2) / self.zoom + self.y
end

function Camera:toScreen(worldX, worldY)
    local w, h = love.graphics.getDimensions()
    return (worldX - self.x) * self.zoom + w / 2,
           (worldY - self.y) * self.zoom + h / 2
end

-- x1, y1, x2, y2 of the visible world rect, for culling
function Camera:view()
    local halfW, halfH = self:halfExtents()
    return self.x - halfW, self.y - halfH, self.x + halfW, self.y + halfH
end

return Camera
