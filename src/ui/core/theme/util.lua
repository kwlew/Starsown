--- Small widget helpers that aren't drawing: hit-testing, easing, labels.

local Metrics = require("ui.core.theme.metrics")

local Util = {}

---@param px number
---@param py number
---@param x number
---@param y number
---@param w number
---@param h number
---@return boolean
function Util.pointIn(px, py, x, y, w, h)
    return px >= x and px <= x + w and py >= y and py <= y + h
end

--- linear, dt-clamped easing toward a moving target -- the UI's standard
-- "chase this value"
---@param current number
---@param target number
---@param dt number
---@param speed? number # defaults to the theme's focusSpeed
---@return number
function Util.approach(current, target, dt, speed)
    return current + (target - current) * math.min(dt * (speed or Metrics.metrics.focusSpeed), 1)
end

--- a label may be a string or a function of its widget, so a control whose
-- text depends on its own value (a toggle, a selector) needs no refresh call
---@param label? string|fun(owner: table): string
---@param owner table # passed to a function label
---@return string
function Util.resolveLabel(label, owner)
    if type(label) == "function" then
        return label(owner)
    end
    return label or ""
end

return Util
