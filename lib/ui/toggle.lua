-- lib/ui/toggle.lua
-- Labeled ON/OFF switch row: label on the left, sliding pill on the right.
-- Enter/click flips it; left/right arrows set it explicitly (left = off).
--
--   local t = Toggle.new{ label = "Fullscreen", value = false,
--                         onChange = function(v) ... end }

local Theme = require "lib.ui.theme"

local Toggle = {}
Toggle.__index = Toggle

local PILL_W, PILL_H = 58, 26

function Toggle.new(config)
    local value = config.value or false
    return setmetatable({
        label = config.label or "",
        value = value,
        onChange = config.onChange,
        font = config.font or Theme.font("body"),
        x = config.x or 0,
        y = config.y or 0,
        w = config.w or 260,
        h = config.h or Theme.metrics.rowHeight,
        focused = false,
        glow = 0,
        knob = value and 1 or 0, -- eased 0..1 knob position
        time = 0,
    }, Toggle)
end

function Toggle:contains(px, py)
    return Theme.pointIn(px, py, self.x, self.y, self.w, self.h)
end

function Toggle:labelText()
    return Theme.resolveLabel(self.label, self)
end

function Toggle:set(value)
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

function Toggle:mousepressed(px, py, mouseButton)
    if mouseButton == 1 and self:contains(px, py) then
        self:activate()
    end
end

function Toggle:update(dt)
    self.time = self.time + dt
    self.glow = Theme.approach(self.glow, self.focused and 1 or 0, dt)
    self.knob = Theme.approach(self.knob, self.value and 1 or 0, dt)
end

function Toggle:draw()
    local c, m = Theme.colors, Theme.metrics

    Theme.rowChrome(self.x, self.y, self.w, self.h, self.glow, self.time)

    -- Label, left-aligned.
    Theme.withFont(self.font, function()
        love.graphics.setColor(c.text)
        love.graphics.print(self:labelText(), self.x + m.padding, Theme.centerY(self.y, self.h, self.font))
    end)

    -- Pill track, right-aligned; fills toward accent as the knob slides on.
    -- Explicit segment counts: at these small radii LÖVE's defaults produce
    -- visibly faceted "circles".
    local pillX = self.x + self.w - m.padding - PILL_W
    local pillY = self.y + (self.h - PILL_H) / 2
    love.graphics.setColor(Theme.lerp(c.track, c.accent, self.knob))
    love.graphics.rectangle("fill", pillX, pillY, PILL_W, PILL_H, PILL_H / 2, PILL_H / 2, 16)

    -- Knob.
    local knobR = PILL_H / 2 - 3
    local knobX = pillX + PILL_H / 2 + (PILL_W - PILL_H) * self.knob
    love.graphics.setColor(c.text)
    love.graphics.circle("fill", knobX, pillY + PILL_H / 2, knobR, 32)

    love.graphics.setColor(1, 1, 1, 1)
end

return Toggle
