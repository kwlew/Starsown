--- Scalar and colour helpers. No requires; anything may use it.
--
--   Math.clamp(x, 0, 10)
--   Math.Color.blend(a, b, 0.5)

local Math = {}

--- if max < min, returns min
---@param value number
---@param min number
---@param max number
---@return number
function Math.clamp(value, min, max)
    if value > max then value = max end
    if value < min then value = min end
    return value
end

---@param value number
---@return number
function Math.clamp01(value)
    return Math.clamp(value, 0, 1)
end

--- floor(x + 0.5); rounds halves up
---@param value number
---@return integer
function Math.round(value)
    return math.floor(value + 0.5)
end

--- signed shortest difference b - a, in -pi..pi
---@param a number # radians
---@param b number # radians
---@return number
function Math.angleDiff(a, b)
    return (b - a + math.pi) % (math.pi * 2) - math.pi
end

--- interpolates between angles the short way round
---@param a number # radians
---@param b number # radians
---@param t number # 0..1
---@return number
function Math.lerpAngle(a, b, t)
    return a + Math.angleDiff(a, b) * t
end

--- the point `radius` from (x, y) at `angle`
---@return number x
---@return number y
function Math.polar(x, y, angle, radius)
    return x + math.cos(angle) * radius, y + math.sin(angle) * radius
end

--- wraps a 1-based index into 1..count
---@param index integer
---@param count integer
---@return integer
function Math.wrapIndex(index, count)
    return (index - 1) % count + 1
end

--- a uniform float in [min, max)
---@param min number
---@param max number
---@return number
function Math.randRange(min, max)
    return min + math.random() * (max - min)
end

--- inclusive [min, max]
---@param min integer
---@param max integer
---@return integer
function Math.randInt(min, max)
    return math.floor(min + math.random() * (max - min + 1))
end

--- a uniform angle in radians, 0..2pi
---@return number
function Math.randAngle()
    return math.random() * math.pi * 2
end

---@param x number
---@param y number
---@return number
function Math.length(x, y)
    return math.sqrt(x * x + y * y)
end

--- fraction left after dt seconds of exponential decay
---@param rate number # per second
---@param dt number
---@return number
function Math.decay(rate, dt)
    return math.exp(-rate * dt)
end

--- frame-rate independent approach toward target
---@param current number
---@param target number
---@param rate number
---@param dt number
---@return number
function Math.damp(current, target, rate, dt)
    return target + (current - target) * Math.decay(rate, dt)
end

--- RGB arithmetic on {r, g, b} tables, 0..1.
local Color = {}
Math.Color = Color

--- perceived brightness; what tinted() preserves while it recolours
---@param r number
---@param g number
---@param b number
---@return number
function Color.luminance(r, g, b)
    return 0.30 * r + 0.59 * g + 0.11 * b
end

---@param a number
---@param b number
---@param t number # 0..1
---@return number # clamped to 0..1
function Color.mix(a, b, t)
    return Math.clamp01(a + (b - a) * t)
end

---@param a number[] RGB
---@param b number[] RGB
---@param t number # 0..1
---@return number[] RGB
function Color.blend(a, b, t)
    local mix = Color.mix
    return { mix(a[1], b[1], t), mix(a[2], b[2], t), mix(a[3], b[3], t) }
end

--- the hue at full brightness; dark accents still tint
---@param color number[] RGB
---@return number[] RGB
function Color.normalized(color)
    local peak = math.max(color[1], color[2], color[3])
    if peak <= 0 then return { 0, 0, 0 } end
    return { color[1] / peak, color[2] / peak, color[3] / peak }
end

--- pulls a neutral toward a hue, keeping its luminance
---@param base number[] # RGB, a neutral
---@param hue number[] # RGB to tint toward
---@param amount number # 0..1
---@return number[] RGB
function Color.tinted(base, hue, amount)
    local peak = math.max(hue[1], hue[2], hue[3])
    if peak <= 0 or amount <= 0 then
        return { base[1], base[2], base[3] }
    end

    local mix, luminance = Color.mix, Color.luminance
    local nr, ng, nb = hue[1] / peak, hue[2] / peak, hue[3] / peak
    local k = luminance(base[1], base[2], base[3]) / luminance(nr, ng, nb)

    return {
        mix(base[1], Math.clamp01(nr * k), amount),
        mix(base[2], Math.clamp01(ng * k), amount),
        mix(base[3], Math.clamp01(nb * k), amount),
    }
end

--- unclamped; three returns, ready for setColor
---@param a number[] RGB
---@param b number[] RGB
---@param t number # 0..1
---@return number r
---@return number g
---@return number b
function Color.lerp(a, b, t)
    return a[1] + (b[1] - a[1]) * t,
           a[2] + (b[2] - a[2]) * t,
           a[3] + (b[3] - a[3]) * t
end

--- full-saturation colour on the hue wheel
---@param hue number # wraps every 1.0
---@return number r
---@return number g
---@return number b
function Color.fromHue(hue)
    local scaled = (hue % 1) * 6
    local i = math.floor(scaled) % 6
    local f = scaled - math.floor(scaled)
    local q = 1 - f
    if i == 0 then return 1, f, 0
    elseif i == 1 then return q, 1, 0
    elseif i == 2 then return 0, 1, f
    elseif i == 3 then return 0, q, 1
    elseif i == 4 then return f, 0, 1
    end
    return 1, 0, q
end

return Math
