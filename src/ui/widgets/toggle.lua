--- Labelled ON/OFF switch row: label on the left, sliding pill on the right.
-- Enter/click flips it; left/right set it explicitly (left = off).
--
--   local t = Toggle.new{ label = "VSync", value = false, onChange = function(v) ... end }

local Theme = require("ui.core.theme")
local Widget = require("ui.widgets.widget")

local Toggle = Widget.extend({})

local PILL_W, PILL_H = 58, 26 -- design px
local KNOB_INSET = 3

---@param config table # Widget.new's fields, plus value: boolean and onChange: fun(value: boolean)
---@return table
function Toggle.new(config)
    local self = Widget.new(Toggle, config)
    self.value = config.value or false
    self.onChange = config.onChange
    self.knob = self.value and 1 or 0 -- eased 0..1 knob position
    return self
end

--- onChange fires only on an actual change, so a caller can set() freely
---@param value boolean
function Toggle:set(value)
    if not self:isInteractive() or value == self.value then return end
    self.value = value
    if self.onChange then self.onChange(value) end
end

function Toggle:activate()
    self:set(not self.value)
end

---@param direction -1|1 # left sets off, right sets on
function Toggle:adjust(direction)
    self:set(direction > 0)
end

---@param dt number
function Toggle:update(dt)
    Widget.update(self, dt)
    self.knob = Theme.approach(self.knob, self.value and 1 or 0, dt)
end

function Toggle:preferredControlSize()
    return Theme.px(PILL_W), Theme.px(PILL_H)
end

---@return number x
---@return number y
---@return number w
---@return number h
function Toggle:pillRect()
    local w, h = self:preferredControlSize()
    if self.rowLayout then
        local cx, cy, cw, ch = self:controlRect()
        return cx + cw - w, cy + (ch - h) / 2, w, h
    end
    return self.x + self.w - Theme.metrics.padding - w, self.y + (self.h - h) / 2, w, h
end

function Toggle:draw()
    local c = Theme.colors
    local alpha, font = self:alpha(), self:getFont()
    self:drawRow(alpha)

    Theme.pushFont(font)
    self:drawLabel(font, alpha)
    Theme.popFont()

    local x, y, w, h = self:pillRect()
    local tr, tg, tb = Theme.lerp(c.track, c.accentDim, self.knob)
    love.graphics.setColor(tr, tg, tb, alpha)
    love.graphics.rectangle("fill", x, y, w, h, h / 2, h / 2, 64)

    local knobR = h / 2 - Theme.px(KNOB_INSET)
    Theme.setColor(c.knob, alpha)
    love.graphics.circle("fill", x + h / 2 + (w - h) * self.knob, y + h / 2, knobR, 4)

    love.graphics.setColor(1, 1, 1, 1)
end

return Toggle
