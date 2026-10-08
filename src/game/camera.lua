--- Follows a world point; turns it into the draw transform.

local Math = require("utils.math")
local Tile = require("game.tile")
local UI = require("ui")

local Camera = {}
Camera.__index = Camera

local FOLLOW_RATE = 8

---@param world table
---@return table
function Camera.new(world)
    return setmetatable({ world = world, x = nil, y = nil, focusX = nil, focusY = nil }, Camera)
end

---@return number w
---@return number h # the window in design px
function Camera:viewSize()
    local s = Tile.worldScale()
    return love.graphics.getWidth() / s, love.graphics.getHeight() / s
end

--- never shows past the world's edge; centres a small world
---@return number x
---@return number y
function Camera:clamped(x, y)
    local vw, vh = self:viewSize()
    local w, h = self.world.w, self.world.h
    x = vw >= w and w / 2 or Math.clamp(x, vw / 2, w - vw / 2)
    y = vh >= h and h / 2 or Math.clamp(y, vh / 2, h - vh / 2)
    return x, y
end

--- jumps there, no easing
function Camera:cut(x, y)
    self.focusX, self.focusY = x, y
    self.x, self.y = self:clamped(x, y)
end

---@param dt number
function Camera:follow(x, y, dt)
    if self.x == nil or UI.Motion.reduced then return self:cut(x, y) end
    self.focusX, self.focusY = x, y
    x, y = self:clamped(x, y)
    local t = 1 - Math.decay(FOLLOW_RATE, dt)
    self.x, self.y = self.x + (x - self.x) * t, self.y + (y - self.y) * t
end

--- keeps the view inside the world after a resize
function Camera:reclamp()
    if self.x then self.x, self.y = self:clamped(self.x, self.y) end
end

--- one axis of offset(). Anchored on the focus's whole pixel plus the
-- rounded lag: sprites round their own position, so rounding the camera
-- separately made the followed sprite step back 1px while it walked.
local function axisOffset(screen, focus, camera, s)
    if not focus then return Math.round(screen / 2 - camera * s) end
    return Math.round(screen / 2) - Math.round(focus * s) + Math.round((focus - camera) * s)
end

--- whole pixels, so pixel art doesn't shimmer
---@return number x
---@return number y
function Camera:offset()
    local s = Tile.worldScale()
    local x, y = self:clamped(self.x or 0, self.y or 0)
    return axisOffset(love.graphics.getWidth(), self.focusX, x, s),
        axisOffset(love.graphics.getHeight(), self.focusY, y, s)
end

---@return number x
---@return number y # design-space world position
function Camera:toWorld(sx, sy)
    local ox, oy = self:offset()
    local s = Tile.worldScale()
    return (sx - ox) / s, (sy - oy) / s
end

---@return number x
---@return number y
---@return number w
---@return number h # the visible world, design px
function Camera:view()
    local ox, oy = self:offset()
    local s = Tile.worldScale()
    local vw, vh = self:viewSize()
    return -ox / s, -oy / s, vw, vh
end

--- a random point on the view's edge, inside the world
---@return number x
---@return number y
function Camera:edgePoint()
    local x, y, w, h = self:view()
    local t, side = math.random(), Math.randInt(1, 4)
    local px, py
    if side == 1 then px, py = x + t * w, y
    elseif side == 2 then px, py = x + t * w, y + h
    elseif side == 3 then px, py = x, y + t * h
    else px, py = x + w, y + t * h end
    return Math.clamp(px, 0, self.world.w), Math.clamp(py, 0, self.world.h)
end

function Camera:attach()
    love.graphics.push()
    love.graphics.translate(self:offset())
end

function Camera:detach()
    love.graphics.pop()
end

return Camera
