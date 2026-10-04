--- Entity mixin: drawing the sprite, or a circle without one.

local Math = require("utils.math")
local Textures = require("game.textures")
local Tile = require("game.tile")
local UI = require("ui")

local Body = {}

---@return number[] # the theme colour standing for this entity
function Body:color()
    return UI.Theme.colors[self.tint or self.fallbackColor]
end

---@param alpha number
---@return number x
---@return number y # between the last two ticks
function Body:lerpPosition(alpha)
    return self.prevX + (self.x - self.prevX) * alpha, self.prevY + (self.y - self.prevY) * alpha
end

---@param alpha number
---@return number # facing to draw
function Body:drawAngle(x, y, alpha)
    return Math.lerpAngle(self.prevAngle, self.angle, alpha)
end

--- also remembers the pose, so a death effect starts where it was seen
---@param alpha number # 0..1 into the next tick
function Body:draw(alpha)
    local x, y = self:lerpPosition(alpha)
    local angle = self:drawAngle(x, y, alpha)
    self.drawnX, self.drawnY, self.drawnAngle = x, y, angle
    self:drawBody(x, y, angle, self:hurtAlpha())
end

--- also how a death effect draws a dead entity
---@param dx number # design px
---@param dy number
---@param angle number
---@param opacity number
function Body:drawBody(dx, dy, angle, opacity)
    local s = Tile.worldScale()
    local x, y = dx * s, dy * s
    local image = self.texture and Textures.get(self.texture)
    if image then
        if self.tint then
            UI.Theme.setColor(UI.Theme.colors[self.tint], opacity)
        else
            love.graphics.setColor(1, 1, 1, opacity)
        end
        local w, h = image:getDimensions()
        local scale = Tile.pixelScale() -- every texel the same size
        love.graphics.draw(image, Math.round(x), Math.round(y), angle - self.spriteAngle, scale, scale, w / 2, h / 2)
    else
        UI.Theme.setColor(self:color(), opacity)
        love.graphics.circle("fill", x, y, self.radius * s, 32)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return Body
