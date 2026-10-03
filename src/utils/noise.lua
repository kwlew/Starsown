--- Seeded 2D value noise. Pure: same input, same output.

local bit = require("bit")

local Noise = {}

local OCTAVE_SEED_STEP = 101

--- 32-bit wrapping multiply; plain `*` loses low bits
local function mul(a, b)
    local low, high = b % 65536, math.floor(b / 65536)
    return bit.tobit(a * low + bit.lshift(bit.band(a * high, 0xffff), 16))
end

--- a lattice point's value, in [0, 1)
---@param x integer
---@param y integer
---@param seed integer
---@return number
function Noise.hash(x, y, seed)
    local h = bit.bxor(mul(x, 0x27d4eb2d), mul(y, 0x165667b1), mul(seed, 0x9e3779b1))
    h = mul(bit.bxor(h, bit.rshift(h, 15)), 0x85ebca6b)
    h = mul(bit.bxor(h, bit.rshift(h, 13)), 0xc2b2ae35)
    h = bit.bxor(h, bit.rshift(h, 16))
    return (h % 4294967296) / 4294967296
end

local function smooth(t)
    return t * t * (3 - 2 * t)
end

--- one octave, in [0, 1)
---@param seed integer
---@return number
function Noise.value(x, y, seed)
    local hash = Noise.hash
    local x0, y0 = math.floor(x), math.floor(y)
    local tx, ty = smooth(x - x0), smooth(y - y0)
    local top = hash(x0, y0, seed) * (1 - tx) + hash(x0 + 1, y0, seed) * tx
    local bottom = hash(x0, y0 + 1, seed) * (1 - tx) + hash(x0 + 1, y0 + 1, seed) * tx
    return top * (1 - ty) + bottom * ty
end

--- layered octaves, each half as loud, twice as fine
---@param seed integer
---@param octaves integer
---@return number # in [0, 1)
function Noise.fbm(x, y, seed, octaves)
    local sum, total, amplitude, frequency = 0, 0, 1, 1
    for octave = 1, octaves do
        sum = sum + amplitude * Noise.value(x * frequency, y * frequency, seed + octave * OCTAVE_SEED_STEP)
        total = total + amplitude
        amplitude, frequency = amplitude * 0.5, frequency * 2
    end
    return sum / total
end

return Noise
