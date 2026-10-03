--- Easing curves: time 0..1 to position 0..1.
-- For fixed durations; moving targets use Theme.approach.

local Ease = {}

--- decelerating; the general-purpose "settles into place" curve
---@param t number # normalized time, 0..1
---@return number
function Ease.outCubic(t)
    local f = 1 - t
    return 1 - f * f * f
end

--- accelerating; a wind-up
---@param t number
---@return number
function Ease.inCubic(t)
    return t * t * t
end

--- both ends eased
---@param t number
---@return number
function Ease.inOutCubic(t)
    if t < 0.5 then return 4 * t * t * t end
    local f = -2 * t + 2
    return 1 - f * f * f / 2
end

--- a gentler outCubic
---@param t number
---@return number
function Ease.outQuad(t)
    return 1 - (1 - t) * (1 - t)
end

local BACK = 1.70158

--- overshoots past 1, then settles; reads as a pop
---@param t number
---@return number
function Ease.outBack(t)
    local f = t - 1
    return 1 + (BACK + 1) * f * f * f + BACK * f * f
end

--- fast start, long tail; flashes and hits
---@param t number
---@return number
function Ease.outExpo(t)
    if t >= 1 then return 1 end
    return 1 - 2 ^ (-10 * t)
end

return Ease
