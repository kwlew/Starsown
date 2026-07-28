-- lib/ui/toggle.lua
-- Labeled ON/OFF switch row: label on the left, sliding pill on the right.
-- Enter/click flips it; left/right arrows set it explicitly (left = off).
--
--   local t = Toggle.new{ label = "VSync", value = false,
--                         onChange = function(v) ... end }

local Theme = require "lib.ui.theme"
local Widget = require "lib.ui.widget"

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

-- Returns false: a toggle has no drag, so it never captures the mouse.
function Toggle:mousepressed(px, py, mouseButton)
    if mouseButton == 1 and self:contains(px, py) then
        self:activate()
    end
    return false
end

function Toggle:update(dt)
    Widget.update(self, dt)
    self.knob = Theme.approach(self.knob, self.value and 1 or 0, dt)
end

function Toggle:draw()
    local c, m = Theme.colors, Theme.metrics
    -- Disabled rows render dimmed and never glow (update forces the glow to 0).
    local alpha = self:alpha()
    local font = self:getFont()

    Theme.rowChrome(self.x, self.y, self.w, self.h, self.glow, self.time, alpha)

    -- Label, left-aligned.
    Theme.pushFont(font)
    love.graphics.setColor(c.text[1], c.text[2], c.text[3], alpha)
    love.graphics.print(self:labelText(), self.x + m.padding, Theme.centerY(self.y, self.h, font))
    Theme.popFont()

    -- Pill track, right-aligned; fills toward accent as the knob slides on.
    -- Explicit segment counts: at these small radii LÖVE's defaults produce
    -- visibly faceted "circles".
    local pillW, pillH = Theme.px(PILL_W), Theme.px(PILL_H)
    local pillX = self.x + self.w - m.padding - pillW
    local pillY = self.y + (self.h - pillH) / 2
    local tr, tg, tb = Theme.lerp(c.track, c.accent, self.knob)
    love.graphics.setColor(tr, tg, tb, alpha)
    love.graphics.rectangle("fill", pillX, pillY, pillW, pillH, pillH / 2, pillH / 2, 64)

    -- Knob.
    local knobR = pillH / 2 - Theme.px(KNOB_INSET)
    local knobX = pillX + pillH / 2 + (pillW - pillH) * self.knob
    love.graphics.setColor(c.text[1], c.text[2], c.text[3], alpha)
    love.graphics.circle("fill", knobX, pillY + pillH / 2, knobR, 32)

    love.graphics.setColor(1, 1, 1, 1)
end

return Toggle
