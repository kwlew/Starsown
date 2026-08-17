-- src/ui/toggle.lua
-- Labeled ON/OFF switch row: label on the left, sliding pill on the right.
-- Enter/click flips it; left/right arrows set it explicitly (left = off).
--
--   local t = Toggle.new{ label = "VSync", value = false,
--                         onChange = function(v) ... end }

local Theme = require "ui.core.theme"
local Widget = require "ui.widgets.widget"

local Toggle = {}
Widget.extend(Toggle)

-- Design-space px, scaled through Theme.px at use.
local PILL_W, PILL_H = 58, 26
local KNOB_INSET = 3

function Toggle.new(config)
    local self = Widget.new(Toggle, config)
    self.value = config.value or false
    self.onChange = config.onChange
    self.knob = self.value and 1 or 0 -- eased 0..1 knob position
    return self
end

function Toggle:set(value)
    if not self:isInteractive() then return end
    if value == self.value then return end
    self.value = value
    if self.onChange then
        self.onChange(value)
    end
end

function Toggle:activate()
    self:set(not self.value)
end

-- Keyboard left/right: right switches on, left switches off.
function Toggle:adjust(direction)
    self:set(direction > 0)
end

function Toggle:update(dt)
    Widget.update(self, dt)
    self.knob = Theme.approach(self.knob, self.value and 1 or 0, dt)
end

function Toggle:draw()
    local c, m = Theme.colors, Theme.metrics
    local alpha, font = self:alpha(), self:getFont()
    self:drawRow(alpha)

    Theme.pushFont(font)
    self:drawLabel(font, alpha)
    Theme.popFont()

    -- Pill track.
    local pillW, pillH = Theme.px(PILL_W), Theme.px(PILL_H)
    local pillX = self.x + self.w - m.padding - pillW
    local pillY = self.y + (self.h - pillH) / 2
    local tr, tg, tb = Theme.lerp(c.track, c.accent, self.knob)
    love.graphics.setColor(tr, tg, tb, alpha)
    love.graphics.rectangle("fill", pillX, pillY, pillW, pillH, pillH / 2, pillH / 2, 64)

    -- Knob.
    local knobR = pillH / 2 - Theme.px(KNOB_INSET)
    local knobX = pillX + pillH / 2 + (pillW - pillH) * self.knob
    Theme.setColor(c.text, alpha)
    love.graphics.circle("fill", knobX, pillY + pillH / 2, knobR, 4)

    love.graphics.setColor(1, 1, 1, 1)
end

return Toggle
