--- The UI scale and the spacing metrics derived from it. Everything is
-- authored against a 720p height and scaled from there.

local Math = require("utils.math")

local Metrics = {}

Metrics.DESIGN_HEIGHT = 720

local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.85, 1.6, 0.05

--- scaled with the UI
local baseMetrics = {
    radius     = 5,
    padding    = 14,
    rowHeight  = 48,
    rowGap     = 14,
    glowSpread = 2,
}

--- the same at every scale
local constantMetrics = {
    glowLayers = 3,
    glowAlpha  = 0.26,
    focusSpeed = 10,
}

--- live values; written in place, so callers may hold on to the table
Metrics.metrics = {}
Metrics.scale = 0

--- snapped to SCALE_STEP so a slow window drag doesn't rebuild fonts every pixel
---@param height number # window height in pixels
---@return number
local function scaleForHeight(height)
    local s = Math.clamp(height / Metrics.DESIGN_HEIGHT, SCALE_MIN, SCALE_MAX)
    return Math.round(s / SCALE_STEP) * SCALE_STEP
end

--- recomputes the scale and metrics for a window height. Doesn't touch any
-- cache built at the old scale -- theme.lua's rescale owns that.
---@param height number # window height in pixels
---@return boolean changed
function Metrics.rescale(height)
    local s = scaleForHeight(height)
    if s == Metrics.scale then return false end
    Metrics.scale = s

    for key, value in pairs(baseMetrics) do
        Metrics.metrics[key] = Math.round(value * s)
    end
    for key, value in pairs(constantMetrics) do
        Metrics.metrics[key] = value
    end
    return true
end

--- design space (authored against a 720p height) to screen pixels; every
-- literal pixel constant in the project goes through here before it's drawn
---@param value number
---@return integer
function Metrics.px(value)
    return Math.round(value * Metrics.scale)
end

Metrics.rescale(Metrics.DESIGN_HEIGHT)

return Metrics
