--- A shooting star's current colour, fade and flicker.

local Color = require("utils.math").Color

local Look = {}

local RAINBOW_CYCLE = 0.15
local RAINBOW_TRAIL_SPAN = 0.6
local FLARE_FRAC = 0.35 -- of the dying window spent brightening
local FLARE_GLOW = 1.75
local COLOR_FRAC = 0.12 -- of the dying window spent recolouring

---@param s table
---@param threshold number # life fraction where burn-out starts
---@return number # 0..1
function Look.dying(s, threshold)
    local ratio = s.life / s.maxLife
    if ratio <= threshold then return 0 end
    return (ratio - threshold) / (1 - threshold)
end

---@param s table
---@return number # about 1 +/- twinkleAmount
function Look.flicker(s)
    local p = s.twinklePhase
    return 1 + s.twinkleAmount * (0.62 * math.sin(p) + 0.38 * math.sin(p * 2.37 + 1.3))
end

--- brightens into a flare, then fades
---@param dying number
---@return number fade
---@return number glow
---@return number colorMix
local function burnOut(dying)
    local colorMix = math.min(1, dying / COLOR_FRAC)
    if dying <= FLARE_FRAC then
        return 1, 1 + dying / FLARE_FRAC * (FLARE_GLOW - 1), colorMix
    end
    local k = 1 - (dying - FLARE_FRAC) / (1 - FLARE_FRAC)
    return k, FLARE_GLOW * k, colorMix
end

---@param s table
---@param dying number
---@return number fade
---@return number glow
---@return number r
---@return number g
---@return number b
function Look.of(s, dying)
    local fade, glow, colorMix = 1, 1, 0
    if dying > 0 then fade, glow, colorMix = burnOut(dying) end
    if s.rainbow then
        local r, g, b = Color.fromHue(s.life * RAINBOW_CYCLE)
        return fade, glow, r, g, b
    end
    local r, g, b = Color.lerp(s.color, s.flare, colorMix)
    return fade, glow, r, g, b
end

--- a rainbow star's hue further back along its trail
---@param s table
---@param t number # 0 head .. 1 tail
---@return number r
---@return number g
---@return number b
function Look.trailHue(s, t)
    return Color.fromHue(s.life * RAINBOW_CYCLE - t * RAINBOW_TRAIL_SPAN)
end

return Look
