-- How height becomes screen space.
--
-- A body's (x, y) is where it *stands*: the ground point everything gameplay
-- cares about -- aim, hit tests, spawn distance, draw order. Where it gets
-- painted is a different point, and that projection lives here rather than
-- being a constant copied into every drawer, so raising a body off the floor
-- later is a change to these numbers and nothing else.
--
--   love.graphics.circle("fill", e.x, e:drawY(), e.radius * Perspective.scale(e.z))

local Perspective = {}

-- Painted above its own feet even at z = 0, or the shadow would be perfectly
-- hidden under the body and there would be no ground plane to read. A fraction
-- of the body's radius, so a small body doesn't hover.
Perspective.STAND = 0.5

-- world units up the screen per unit of height: 1 means a body one tile up
-- draws exactly one tile north of its shadow
local LIFT = 1.0

-- how much bigger a body reads as it rises. Tiny on purpose -- a depth cue,
-- not a zoom.
local SCALE = 0.0016

-- the shadow shrinks and fades on one curve, so a body high up has a small
-- faint mark under it rather than a hard disc that never changes
local SHRINK = 0.006

Perspective.SHADOW_SPREAD = 1.1  -- of the body radius, so it peeks out at the sides
Perspective.SHADOW_SQUASH = 0.42 -- the ground is being looked at from an angle
Perspective.SHADOW_ALPHA = 0.5

function Perspective.lift(z)
    return (z or 0) * LIFT
end

function Perspective.scale(z)
    return 1 + (z or 0) * SCALE
end

-- 1 on the ground, falling off with height; scales the shadow's size and its
-- opacity together
function Perspective.shadowFade(z)
    return 1 / (1 + (z or 0) * SHRINK)
end

return Perspective
