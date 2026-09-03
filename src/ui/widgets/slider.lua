--- Labeled 0..1 slider row: label left, draggable track + percentage right.
-- onChange(value) fires on every change (apply live); onRelease(value)
-- fires when a drag ends or after a keyboard step (persist here).
--
--   local s = Slider.new{ label = "Volume", value = 0.8, step = 0.1,
--                         onChange = function(v) ... end,
--                         onRelease = function(v) ... end }
--
-- Only the track grabs the mouse (see mousepressed); a drag in progress
-- captures it from the owning FocusGroup so it keeps tracking off-widget.

local Theme = require "ui.core.theme"
local Widget = require "ui.widgets.widget"
local Math = require "utils.math"

local Slider = {}
Widget.extend(Slider)

local TRACK_H = 8
local PERCENT_W = 52    -- reserved width for the "100%" readout
local KNOB_RATIO = 1.125 -- knob radius as a multiple of track height, stays proportional at every scale
local KNOB_CLEARANCE = 4 -- clearance past the track's end, or the knob at 100% prints through "100%"
local GRAB_MARGIN = 12

---@param config table # Widget.new's fields, plus value: number 0..1, step: number, onChange: fun(value: number), onRelease: fun(value: number)
---@return table
function Slider.new(config)
    local self = Widget.new(Slider, config)
    self.value = config.value or 0
    self.step = config.step or 0.1
    self.onChange = config.onChange
    self.onRelease = config.onRelease
    self.dragging = false
    return self
end

---@return boolean # lit through a whole drag, not just while focused
function Slider:isLit()
    return self.focused or self.dragging
end

--- right-aligned, leaving room for the label on the left and readout (plus knob clearance) on the right
---@return number x
---@return number y
---@return number w
---@return number h
function Slider:trackRect()
    local m = Theme.metrics
    local trackH = Theme.px(TRACK_H)
    local gap = trackH * KNOB_RATIO + Theme.px(KNOB_CLEARANCE)
    local trackW = math.floor(self.w * 0.42)
    local trackX = self.x + self.w - m.padding - Theme.px(PERCENT_W) - gap - trackW
    local trackY = self.y + (self.h - trackH) / 2
    return trackX, trackY, trackW, trackH
end

--- grab area: the track grown by GRAB_MARGIN, clamped to the row so it can't reach a neighbouring widget
---@param px number
---@param py number
---@return boolean
function Slider:trackContains(px, py)
    local trackX, trackY, trackW, trackH = self:trackRect()
    local margin = Theme.px(GRAB_MARGIN)
    local top = math.max(self.y, trackY - margin)
    local bottom = math.min(self.y + self.h, trackY + trackH + margin)
    return Theme.pointIn(px, py,
        trackX - margin, top,
        trackW + margin * 2, bottom - top)
end

--- clamped to 0..1 and rounded to whole percent; onChange fires only on a
-- real change
---@param value number
function Slider:setValue(value)
    if not self:isInteractive() then return end
    value = Math.round(Math.clamp01(value) * 100) / 100 -- keep values (and saves) tidy
    if value == self.value then return end
    self.value = value
    if self.onChange then
        self.onChange(value)
    end
end

--- one keyboard step, which counts as a commit (onRelease fires too)
---@param direction -1|1
function Slider:adjust(direction)
    if not self:isInteractive() then return end
    self:setValue(self.value + direction * self.step)
    if self.onRelease then
        self.onRelease(self.value)
    end
end

---@param self table
---@param px number # screen x
---@return number # unclamped 0..1 ratio along the track
local function valueFromX(self, px)
    local trackX, _, trackW = self:trackRect()
    return (px - trackX) / trackW
end

--- only a press on the track (plus grab margin) starts a drag -- hit-testing
-- the whole row would let a click on the far-left label compute a negative
-- ratio and snap to 0, muting the game by clicking its own name
---@param px number
---@param py number
---@param mouseButton integer
---@return boolean # captured true once a drag starts, so the FocusGroup keeps routing here
function Slider:mousepressed(px, py, mouseButton)
    if mouseButton ~= 1 or not self:isInteractive() then return false end
    if not self:trackContains(px, py) then return false end

    self.dragging = true
    self:setValue(valueFromX(self, px))
    return true
end

---@param px number
---@param py number
function Slider:mousemoved(px, py)
    if self.dragging then
        self:setValue(valueFromX(self, px))
    end
end

--- ends a drag and commits through onRelease -- the point where a live-applied
-- value gets persisted
---@param px number
---@param py number
---@param mouseButton integer
function Slider:mousereleased(px, py, mouseButton)
    if mouseButton == 1 and self.dragging then
        self.dragging = false
        if self.onRelease then
            self.onRelease(self.value)
        end
    end
end

--- label left, then the track, fill, knob and percentage readout
function Slider:draw()
    local c, m = Theme.colors, Theme.metrics
    local alpha, font = self:alpha(), self:getFont()
    self:drawRow(alpha)

    Theme.pushFont(font)
    self:drawLabel(font, alpha)

    local trackX, trackY, trackW, trackH = self:trackRect()
    Theme.setColor(c.track, alpha)
    love.graphics.rectangle("fill", trackX, trackY, trackW, trackH, trackH / 2, trackH / 2, 12)
    Theme.setColor(c.accentDim, alpha)
    love.graphics.rectangle("fill", trackX, trackY, trackW * self.value, trackH, trackH / 2, trackH / 2, 12)
    Theme.setColor(c.knob, alpha)
    love.graphics.circle("fill", trackX + trackW * self.value, trackY + trackH / 2,
        trackH * KNOB_RATIO, 4)

    local smallFont = Theme.font("small")
    local percentW = Theme.px(PERCENT_W)
    Theme.pushFont(smallFont)
    Theme.setColor(c.textDim, alpha)
    love.graphics.printf(Math.round(self.value * 100) .. "%",
        self.x + self.w - m.padding - percentW,
        Theme.centerY(self.y, self.h, smallFont), percentW, "right")
    Theme.popFont()

    Theme.popFont()
    love.graphics.setColor(1, 1, 1, 1)
end

return Slider
