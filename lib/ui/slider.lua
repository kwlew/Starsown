-- lib/ui/slider.lua
-- Labeled 0..1 slider row: label left, draggable track + percentage right.
-- onChange(value) fires on every change (apply live); onRelease(value) fires
-- when a drag ends or after a keyboard step (persist here).
--
--   local s = Slider.new{ label = "Volume", value = 0.8, step = 0.1,
--                         onChange = function(v) ... end,
--                         onRelease = function(v) ... end }

local Theme = require "lib.ui.theme"

local Slider = {}
Slider.__index = Slider

local TRACK_H = 8
local PERCENT_W = 52 -- reserved width for the "100%" readout

function Slider.new(config)
    return setmetatable({
        label = config.label or "",
        value = config.value or 0,
        step = config.step or 0.1, -- keyboard left/right increment
        onChange = config.onChange,
        onRelease = config.onRelease,
        font = config.font or Theme.font("body"),
        x = config.x or 0,
        y = config.y or 0,
        w = config.w or 260,
        h = config.h or Theme.metrics.rowHeight,
        focused = false,
        dragging = false,
        glow = 0,
        time = 0,
    }, Slider)
end

function Slider:contains(px, py)
    return Theme.pointIn(px, py, self.x, self.y, self.w, self.h)
end

function Slider:labelText()
    return Theme.resolveLabel(self.label, self)
end

-- Track geometry: right-aligned, leaving room for label and percentage.
function Slider:trackRect()
    local m = Theme.metrics
    local trackW = math.floor(self.w * 0.42)
    local trackX = self.x + self.w - m.padding - PERCENT_W - trackW
    local trackY = self.y + (self.h - TRACK_H) / 2
    return trackX, trackY, trackW, TRACK_H
end

function Slider:setValue(value)
    value = math.max(0, math.min(1, value))
    value = math.floor(value * 100 + 0.5) / 100 -- keep values (and saves) tidy
    if value == self.value then return end
    self.value = value
    if self.onChange then
        self.onChange(value)
    end
end

-- Keyboard left/right. Fires onRelease too, since the change is final.
function Slider:adjust(direction)
    self:setValue(self.value + direction * self.step)
    if self.onRelease then
        self.onRelease(self.value)
    end
end

local function valueFromX(self, px)
    local trackX, _, trackW = self:trackRect()
    return (px - trackX) / trackW
end

function Slider:mousepressed(px, py, mouseButton)
    if mouseButton == 1 and self:contains(px, py) then
        self.dragging = true
        self:setValue(valueFromX(self, px))
    end
end

function Slider:mousemoved(px, py)
    if self.dragging then
        self:setValue(valueFromX(self, px))
    end
end

function Slider:mousereleased(px, py, mouseButton)
    if mouseButton == 1 and self.dragging then
        self.dragging = false
        if self.onRelease then
            self.onRelease(self.value)
        end
    end
end

function Slider:update(dt)
    self.time = self.time + dt
    self.glow = Theme.approach(self.glow, (self.focused or self.dragging) and 1 or 0, dt)
end

function Slider:draw()
    local c, m = Theme.colors, Theme.metrics

    Theme.rowChrome(self.x, self.y, self.w, self.h, self.glow, self.time)

    local previousFont = love.graphics.getFont()
    love.graphics.setFont(self.font)

    -- Label, left-aligned.
    love.graphics.setColor(c.text)
    love.graphics.print(self:labelText(), self.x + m.padding, Theme.centerY(self.y, self.h, self.font))

    -- Track, fill, knob. Explicit segment counts: at these small radii LÖVE's
    -- defaults produce visibly faceted "circles".
    local trackX, trackY, trackW, trackH = self:trackRect()
    love.graphics.setColor(c.track)
    love.graphics.rectangle("fill", trackX, trackY, trackW, trackH, trackH / 2, trackH / 2, 12)
    love.graphics.setColor(c.accent)
    love.graphics.rectangle("fill", trackX, trackY, trackW * self.value, trackH, trackH / 2, trackH / 2, 12)
    love.graphics.setColor(c.text)
    love.graphics.circle("fill", trackX + trackW * self.value, trackY + trackH / 2, 9, 4)

    -- Percentage readout, right-aligned in the small font so it can't
    -- overflow its reserved column.
    local smallFont = Theme.font("small")
    love.graphics.setFont(smallFont)
    love.graphics.setColor(c.textDim)
    local percent = math.floor(self.value * 100 + 0.5) .. "%"
    local percentY = Theme.centerY(self.y, self.h, smallFont)
    love.graphics.printf(percent, self.x + self.w - m.padding - PERCENT_W, percentY, PERCENT_W, "right")

    love.graphics.setFont(previousFont)
    love.graphics.setColor(1, 1, 1, 1)
end

return Slider
