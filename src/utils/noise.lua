-- Seeded 2D value noise. Pure and stateless: the same (x, y, seed) always gives
-- the same value, so an unbounded world can be sampled anywhere, in any order,
-- with nothing stored.

local bit = require "bit"

local Noise = {}

--- 32-bit wrapping multiply; a plain `a * b` would lose low bits past 2^53
local function mul(a, b)
    local low, high = b % 65536, math.floor(b / 65536)
    return bit.tobit(a * low + bit.lshift(bit.band(a * high, 0xffff), 16))
end

--- a lattice point's value, uniform in [0, 1); also exported as Noise.hash for
-- anything wanting a stateless random number keyed on (x, y, seed)
local function hash(x, y, seed)
    local h = bit.bxor(mul(x, 0x27d4eb2d), mul(y, 0x165667b1), mul(seed, 0x9e3779b1))
    h = mul(bit.bxor(h, bit.rshift(h, 15)), 0x85ebca6b)
    h = mul(bit.bxor(h, bit.rshift(h, 13)), 0xc2b2ae35)
    h = bit.bxor(h, bit.rshift(h, 16))
    return (h % 4294967296) / 4294967296
end

Noise.hash = hash

local function smooth(t)
    return t * t * (3 - 2 * t)
end

--- one octave of value noise, in [0, 1)
---@param x number
---@param y number
---@param seed integer
---@return number
function Noise.value(x, y, seed)
    local x0, y0 = math.floor(x), math.floor(y)
    local tx, ty = smooth(x - x0), smooth(y - y0)
    local top = hash(x0, y0, seed) * (1 - tx) + hash(x0 + 1, y0, seed) * tx
    local bottom = hash(x0, y0 + 1, seed) * (1 - tx) + hash(x0 + 1, y0 + 1, seed) * tx
    return top * (1 - ty) + bottom * ty
end

--- Layered octaves: broad shapes first, finer detail on top, each half as loud
-- and twice as fine. Normalized back to [0, 1).
---@param x number
---@param y number
---@param seed integer
---@param octaves integer
---@return number
function Noise.fbm(x, y, seed, octaves)
    local sum, total, amplitude, frequency = 0, 0, 1, 1
    for octave = 1, octaves do
        sum = sum + amplitude * Noise.value(x * frequency, y * frequency, seed + octave * 101)
        total = total + amplitude
        amplitude, frequency = amplitude * 0.5, frequency * 2
    end
    return sum / total
end

return Noise
