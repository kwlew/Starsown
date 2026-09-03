--- How height becomes screen space.
--
-- A body's (x, y) is where it *stands*: the ground point everything gameplay
-- cares about -- aim, hit tests, spawn distance, draw order. Where it gets
-- painted is a different point, and that projection lives here rather than
-- being a constant copied into every drawer, so raising a body off the floor
-- later is a change to these numbers and nothing else.
--
--   love.graphics.circle("fill", e.x, e:drawY(), e.radius * Perspective.scale(e.z))

local Perspective = {}

Perspective.STAND = 0.5

local LIFT = 1.0

local SCALE = 0.0016

local SHRINK = 0.006

Perspective.SHADOW_SPREAD = 1.1  -- of the body radius, so it peeks out at the sides
Perspective.SHADOW_SQUASH = 0.42 -- the ground is being looked at from an angle
Perspective.SHADOW_ALPHA = 0.5

---@param z? number # height above the ground
---@return number # pixels to paint the body above where it stands
function Perspective.lift(z)
    return (z or 0) * LIFT
end

---@param z? number # height above the ground
---@return number # size multiplier, 1 on the ground
function Perspective.scale(z)
    return 1 + (z or 0) * SCALE
end

--- 1 on the ground, falling off with height; scales the shadow's size and its
-- opacity together
---@param z? number # height above the ground
---@return number # 0..1
function Perspective.shadowFade(z)
    return 1 / (1 + (z or 0) * SHRINK)
end

return Perspective
