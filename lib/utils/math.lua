-- lib/utils/math.lua
-- Scalar helpers shared across the UI and the particle effects. Deliberately
-- has no requires, so anything (including lib/ui/theme.lua) may depend on it.

local Math = {}

function Math.randRange(min, max)
    return min + math.random() * (max - min)
end

-- Random integer in [min, max], inclusive. Replaces the
-- math.floor(randRange(min, max + 1)) idiom, whose +1 is easy to drop.
function Math.randInt(min, max)
    return math.floor(min + math.random() * (max - min + 1))
end

function Math.randAngle()
    return math.random() * math.pi * 2
end

-- Ceiling applied before the floor, so a degenerate max < min yields min. That
-- matches the max(min, math.min(value, max)) idiom this replaces, which
-- Selector:valueColumnWidth depends on: a row too narrow for its value column
-- computes a negative `available` and must collapse to 0, not to the negative.
function Math.clamp(value, min, max)
    if value > max then value = max end
    if value < min then value = min end
    return value
end

function Math.clamp01(value)
    return Math.clamp(value, 0, 1)
end

-- Nearest integer. floor(x + 0.5) rather than a symmetric round, matching every
-- site this replaces (all of which take positive input).
function Math.round(value)
    return math.floor(value + 0.5)
end

function Math.length(x, y)
    return math.sqrt(x * x + y * y)
end

-- Wraps a 1-based index into 1..count, so 0 lands on count and count+1 on 1.
function Math.wrapIndex(index, count)
    return (index - 1) % count + 1
end

return Math
