--- Follows a target around the world. Everything drawn between attach() and
-- detach() is in world coordinates; toWorld/toScreen convert across the seam.
-- The world is open by default, so there is nothing to clamp the view
-- against -- an area with its own `bounds` (see game/areas.lua) is the
-- exception, handled by follow()'s optional third argument.

local Math = require "utils.math"

local Camera = {}
Camera.__index = Camera

local FOLLOW_SPEED = 9 -- exponential approach per second, not per frame

---@param config? table # { x?: number, y?: number, zoom?: number }
---@return table
function Camera.new(config)
    config = config or {}
    return setmetatable({
        x = config.x or 0, -- the world point sitting at the centre of the screen
        y = config.y or 0,
        zoom = config.zoom or 1,
    }, Camera)
end

--- jumps the view, with no easing -- for the start of a run, not for following
---@param x number
---@param y number
function Camera:snapTo(x, y)
    self.x, self.y = x, y
end

--- eases toward a point, frame-rate independently. `bounds`, when given (an
-- area's own `bounds = { w, h }`, centered on that area's local origin),
-- keeps the camera's own view from ever showing past its edges -- omitted,
-- the camera follows unclamped, exactly as it always has.
---@param x number
---@param y number
---@param dt number
---@param bounds? table # { w: number, h: number }
function Camera:follow(x, y, dt, bounds)
    self.x = Math.damp(self.x, x, FOLLOW_SPEED, dt)
    self.y = Math.damp(self.y, y, FOLLOW_SPEED, dt)
    if bounds then self:clampTo(bounds) end
end

--- pulls the camera back inside `bounds` after follow()'s easing step. When
-- the bounded extent is narrower than the view itself on an axis, centers
-- on that axis instead of clamping between two limits that have crossed --
-- the letterboxed edges from World's own checker are the visible result,
-- not an oscillating camera.
---@param bounds table # { w: number, h: number }, centered on the world origin
function Camera:clampTo(bounds)
    local halfW, halfH = self:halfExtents()
    local boundHalfW, boundHalfH = bounds.w / 2, bounds.h / 2

    self.x = boundHalfW <= halfW and 0 or Math.clamp(self.x, -boundHalfW + halfW, boundHalfW - halfW)
    self.y = boundHalfH <= halfH and 0 or Math.clamp(self.y, -boundHalfH + halfH, boundHalfH - halfH)
end

--- half the view, in world units
---@return number halfW
---@return number halfH
function Camera:halfExtents()
    local w, h = love.graphics.getDimensions()
    return w / (2 * self.zoom), h / (2 * self.zoom)
end

--- pushes the world transform; pair with detach()
function Camera:attach()
    local w, h = love.graphics.getDimensions()
    love.graphics.push()
    love.graphics.translate(w / 2, h / 2)
    love.graphics.scale(self.zoom)
    love.graphics.translate(-self.x, -self.y)
end

--- pops back to screen space
function Camera:detach()
    love.graphics.pop()
end

---@param screenX number
---@param screenY number
---@return number x
---@return number y
function Camera:toWorld(screenX, screenY)
    local w, h = love.graphics.getDimensions()
    return (screenX - w / 2) / self.zoom + self.x,
           (screenY - h / 2) / self.zoom + self.y
end

---@param worldX number
---@param worldY number
---@return number x
---@return number y
function Camera:toScreen(worldX, worldY)
    local w, h = love.graphics.getDimensions()
    return (worldX - self.x) * self.zoom + w / 2,
           (worldY - self.y) * self.zoom + h / 2
end

--- x1, y1, x2, y2 of the visible world rect, for culling
---@return number x1
---@return number y1
---@return number x2
---@return number y2
function Camera:view()
    local halfW, halfH = self:halfExtents()
    return self.x - halfW, self.y - halfH, self.x + halfW, self.y + halfH
end

return Camera
