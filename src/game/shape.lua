-- The project's entity art is flat convex primitives, so the polygon is shared
-- rather than owned by whatever needed it first: bodies in the world draw
-- through here and so do item icons in the inventory.

local Math = require "utils.math"

local Shape = {}

-- `sides` is the whole vocabulary until there is art: nil or < 3 is a circle,
-- 3 a triangle, 4 a diamond, and so on
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
