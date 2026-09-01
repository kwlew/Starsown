-- Scalar helpers shared across the UI and the particle effects. No
-- requires, so anything (including ui/core/theme.lua) may depend on it.

local Math = {}

function Math.randRange(min, max)
    return min + math.random() * (max - min)
end

-- inclusive [min, max]; replaces the math.floor(randRange(min, max+1)) idiom, whose +1 is easy to drop
function Math.randInt(min, max)
    return math.floor(min + math.random() * (max - min + 1))
end

function Math.randAngle()
    return math.random() * math.pi * 2
end

-- ceiling applied before the floor, so a degenerate max < min yields min
-- (Selector:valueColumnWidth depends on this: a too-narrow row computes a
-- negative `available` and must collapse to 0, not to the negative)
function Math.clamp(value, min, max)
    if value > max then value = max end
    if value < min then value = min end
    return value
end

function Math.clamp01(value)
    return Math.clamp(value, 0, 1)
end

-- floor(x + 0.5), not a symmetric round, matching every site this replaces (all take positive input)
function Math.round(value)
    return math.floor(value + 0.5)
end

function Math.length(x, y)
    return math.sqrt(x * x + y * y)
end

-- the fraction of a value still left after dt seconds of decaying at `rate`.
-- exp() is what makes it frame-rate independent; a plain per-frame multiply
-- decays faster the more frames a second happens to have.
function Math.decay(rate, dt)
    return math.exp(-rate * dt)
end

-- frame-rate independent approach toward `target`. Distinct from
-- Theme.approach, which is the linear, dt-clamped version the UI eases with.
function Math.damp(current, target, rate, dt)
    return target + (current - target) * Math.decay(rate, dt)
end

-- the point `radius` away from (x, y) at `angle`
function Math.polar(x, y, angle, radius)
    return x + math.cos(angle) * radius, y + math.sin(angle) * radius
end

-- wraps a 1-based index into 1..count, so 0 lands on count and count+1 on 1
function Math.wrapIndex(index, count)
    return (index - 1) % count + 1
end

return Math
