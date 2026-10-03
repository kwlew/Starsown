--- 2D segment tests used to lay out constellations.

local Math = require("utils.math")

local Geometry = {}

---@return number # positive left of a->b, negative right
local function orient(ax, ay, bx, by, cx, cy)
    return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
end

--- proper crossings only; shared endpoints don't count
---@return boolean
function Geometry.segmentsCross(ax, ay, bx, by, cx, cy, dx, dy)
    return orient(cx, cy, dx, dy, ax, ay) * orient(cx, cy, dx, dy, bx, by) < 0
        and orient(ax, ay, bx, by, cx, cy) * orient(ax, ay, bx, by, dx, dy) < 0
end

---@param rect number[] # { x0, y0, x1, y1 }
---@return boolean
function Geometry.inRect(x, y, rect)
    return x > rect[1] and x < rect[3] and y > rect[2] and y < rect[4]
end

--- an end inside, or a crossed diagonal
---@param rect number[]
---@return boolean
function Geometry.segmentHitsRect(ax, ay, bx, by, rect)
    return Geometry.inRect(ax, ay, rect) or Geometry.inRect(bx, by, rect)
        or Geometry.segmentsCross(ax, ay, bx, by, rect[1], rect[2], rect[3], rect[4])
        or Geometry.segmentsCross(ax, ay, bx, by, rect[3], rect[2], rect[1], rect[4])
end

---@param s number[] # { x1, y1, x2, y2 }
---@return number
function Geometry.distanceToSegment(px, py, s)
    local dx, dy = s[3] - s[1], s[4] - s[2]
    local t = Math.clamp01(((px - s[1]) * dx + (py - s[2]) * dy) / (dx * dx + dy * dy))
    return Math.length(px - (s[1] + dx * t), py - (s[2] + dy * t))
end

return Geometry
