-- src/utils/ease.lua
-- Easing curves: pure functions from a normalized time t in 0..1 to a
-- normalized position, also 0..1. Deliberately has no requires, so anything
-- (including src/ui/theme.lua) may depend on it, the same way utils/math.lua
-- does.
--
-- These are for effects with a fixed duration, where something counts a timer
-- down and asks "how far along am I". They are NOT a replacement for
-- Theme.approach, which is the right tool whenever a value is chasing a target
-- that can move — a focus glow, a toggle knob, a gold readout. Between the two
-- there is nothing here that needs a tween manager: every effect in the game is
-- either a follower or a decaying scalar.
--
--   local t = 1 - tower.pop            -- pop counts 1 -> 0
--   local scale = 1 + Ease.outBack(t) * 0.18
--
-- Input is not clamped. Callers derive t from a life fraction they already
-- bound, and outBack/outExpo are meaningful slightly outside 0..1 anyway.

local Ease = {}

function Ease.outCubic(t)
    local f = 1 - t
    return 1 - f * f * f
end

function Ease.inCubic(t)
    return t * t * t
end

function Ease.inOutCubic(t)
    if t < 0.5 then
        return 4 * t * t * t
    end
    local f = -2 * t + 2
    return 1 - f * f * f / 2
end

function Ease.outQuad(t)
    return 1 - (1 - t) * (1 - t)
end

-- Overshoots past 1 and settles back. The scale-pop curve: a tower that lands
-- at exactly its final size reads as fading in, one that overshoots reads as
-- being placed.
local BACK = 1.70158
function Ease.outBack(t)
    local f = t - 1
    return 1 + (BACK + 1) * f * f * f + BACK * f * f
end

-- Very fast out of the gate, then a long tail. For anything that should look
-- like it already happened by the time you notice it — a muzzle flash, a hit
-- flash.
function Ease.outExpo(t)
    if t >= 1 then return 1 end
    return 1 - 2 ^ (-10 * t)
end

return Ease
