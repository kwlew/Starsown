---@diagnostic disable: duplicate-doc-param
--- Labelled 0..1 slider row: label left, draggable track and percentage right.
-- onChange(value) fires on every change (apply live); onRelease(value) when
-- a drag ends or after a keyboard step (persist here).
--
--   local s = Slider.new{ label = "Volume", value = 0.8, step = 0.1,
--                         onChange = function(v) ... end,
--                         onRelease = function(v) ... end }

local Math = require("utils.math")
local Theme = require("ui.core.theme")
local Widget = require("ui.widgets.widget")

local Slider = Widget.extend({})

local TRACK_H = 8
local CONTROL_W, CONTROL_MIN_H = 260, 28 -- preferred measured-row control size
local PERCENT_W = 52     -- reserved width for the "100%" readout
local KNOB_RATIO = 1.125 -- knob radius as a multiple of track height
local KNOB_CLEARANCE = 4 -- past the track's end, or the knob at 100% prints through "100%"
local GRAB_MARGIN = 12
local UNMEASURED_TRACK = 0.42 -- of the row width, without a measured layout

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

function Slider:preferredControlSize(available)
    return math.min(available, Theme.px(CONTROL_W)),
        math.max(Theme.px(CONTROL_MIN_H), self:getFont():getHeight())
end

--- right-aligned, leaving room for the readout (plus knob clearance) on the right
---@return number x
---@return number y
---@return number w
---@return number h
function Slider:trackRect()
    local trackH = Theme.px(TRACK_H)
    local reserved = Theme.px(PERCENT_W) + trackH * KNOB_RATIO + Theme.px(KNOB_CLEARANCE)
    if self.rowLayout then
        local x, y, w, h = self:controlRect()
        return x, y + (h - trackH) / 2, math.max(1, w - reserved), trackH
    end
    local trackW = math.floor(self.w * UNMEASURED_TRACK)
    local trackX = self.x + self.w - Theme.metrics.padding - reserved - trackW
    return trackX, self.y + (self.h - trackH) / 2, trackW, trackH
end

--- the track grown by GRAB_MARGIN, clamped to the row so it can't reach a neighbour
---@param px number
---@param py number
---@return boolean
function Slider:trackContains(px, py)
    local x, y, w, h = self:trackRect()
    local margin = Theme.px(GRAB_MARGIN)
    local top = math.max(self.y, y - margin)
    local bottom = math.min(self.y + self.h, y + h + margin)
    return Theme.pointIn(px, py, x - margin, top, w + margin * 2, bottom - top)
end

--- clamped to 0..1 and rounded to whole percent; onChange fires only on a real change
---@param value number
function Slider:setValue(value)
    if not self:isInteractive() then return end
    value = Math.round(Math.clamp01(value) * 100) / 100 -- keeps values (and saves) tidy
    if value == self.value then return end
    self.value = value
    if self.onChange then self.onChange(value) end
end

---@param px number # screen x
---@return number # unclamped 0..1 ratio along the track
function Slider:valueAt(px)
    local x, _, w = self:trackRect()
    return (px - x) / w
end

--- one keyboard step, which counts as a commit (onRelease fires too)
---@param direction -1|1
function Slider:adjust(direction)
    if not self:isInteractive() then return end
    self:setValue(self.value + direction * self.step)
    if self.onRelease then self.onRelease(self.value) end
end

--- only a press on the track starts a drag -- hit-testing the whole row would
-- let a click on the label compute a negative ratio and snap to 0
---@param px number
---@param py number
---@param mouseButton integer
---@return boolean captured
function Slider:mousepressed(px, py, mouseButton)
    if mouseButton ~= 1 or not self:isInteractive() or not self:trackContains(px, py) then
        return false
    end
    self.dragging = true
    self:setValue(self:valueAt(px))
    return true
end

---@param px number
function Slider:mousemoved(px)
    if self.dragging then self:setValue(self:valueAt(px)) end
end

--- ends a drag and commits through onRelease
---@param _ number
---@param _ number
---@param mouseButton integer
function Slider:mousereleased(_, _, mouseButton)
    if mouseButton ~= 1 or not self.dragging then return end
    self.dragging = false
    if self.onRelease then self.onRelease(self.value) end
end

function Slider:draw()
    local c, m = Theme.colors, Theme.metrics
    local alpha, font = self:alpha(), self:getFont()
    self:drawRow(alpha)

    Theme.pushFont(font)
    self:drawLabel(font, alpha)
    Theme.popFont()

    local x, y, w, h = self:trackRect()
    local radius = h / 2
    Theme.setColor(c.track, alpha)
    love.graphics.rectangle("fill", x, y, w, h, radius, radius, 12)
    Theme.setColor(c.accentDim, alpha)
    love.graphics.rectangle("fill", x, y, w * self.value, h, radius, radius, 12)
    Theme.setColor(c.knob, alpha)
    love.graphics.circle("fill", x + w * self.value, y + h / 2, h * KNOB_RATIO, 4)

    local small = Theme.font("small")
    local percentW = Theme.px(PERCENT_W)
    local rowY, rowH = self.y, self.h
    if self.rowLayout then rowY, rowH = self.y + self.rowLayout.y, self.rowLayout.h end
    Theme.pushFont(small)
    Theme.setColor(c.textDim, alpha)
    love.graphics.printf(Math.round(self.value * 100) .. "%",
        self.x + self.w - m.padding - percentW, Theme.centerY(rowY, rowH, small), percentW, "right")
    Theme.popFont()

    love.graphics.setColor(1, 1, 1, 1)
end

return Slider
