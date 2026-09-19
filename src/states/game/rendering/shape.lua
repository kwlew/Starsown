-- src/states/game/rendering/shape.lua
-- This will be the shape rendering module.

local Math = require "utils.math"

local Shape = {}

--- Draw a shape.
---@param mode string # "fill" or "line"
---@param x number The x-coordinate of the center of the shape.
---@param y number The y-coordinate of the center of the shape.
---@param radius number The radius of the shape.
---@param sides number The number of sides of the shape.
---@param rotation number The rotation of the shape in radians.
function Shape.draw(mode, x, y, radius, sides, rotation)
    if not sides or sides < 3 then
        love.graphics.circle(mode, x, y, radius)
        return
    end

    local step = math.pi * 2 / sides
    local verts = {}

    for i = 1, sides do
        local angle = (rotation or 0) + (i - 1) * step - math.pi / 2
        verts[i * 2 - 1], verts[i * 2] = Math.polar(x, y, angle, radius)
    end

    love.graphics.polygon(mode, verts)
end
return Shape
