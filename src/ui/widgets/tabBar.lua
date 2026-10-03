--- Horizontal segmented tab bar: equal-width segments with a highlight that
-- slides to the active one. Left/right (adjust) or Enter (activate, cycles)
-- switch tabs while it's focused.
--
--   local bar = TabBar.new{ tabs = { "General", "Graphics" }, index = 1,
--                           onChange = function(name, index) ... end }
--
-- Sync the active tab without firing onChange by setting `bar.index` directly.

local Math = require("utils.math")
local Theme = require("ui.core.theme")
local Widget = require("ui.widgets.widget")

local TabBar = Widget.extend({})

TabBar.fontRole = "button"

local SEGMENT_GAP = 6 -- design px

---@param config table # Widget.new's fields, plus tabs: (string|fun(self: table): string)[], index?: integer, onChange?: fun(name: any, index: integer)
---@return table
function TabBar.new(config)
    local self = Widget.new(TabBar, config)
    self.tabs = config.tabs or {}
    self.index = config.index or 1
    self.onChange = config.onChange
    self.highlight = self.index -- eased, continuous position of the active marker
    self.hovered = nil          -- segment index under the pointer
    return self
end

---@param i integer # may be fractional, for the sliding highlight
---@return number x
---@return number y
---@return number w
---@return number h
function TabBar:segmentRect(i)
    local count = math.max(1, #self.tabs)
    local gap = Theme.px(SEGMENT_GAP)
    local segW = (self.w - gap * (count - 1)) / count
    return self.x + (i - 1) * (segW + gap), self.y, segW, self.h
end

---@param px number
---@param py number
---@return integer|nil
function TabBar:segmentAt(px, py)
    for i = 1, #self.tabs do
        if Theme.pointIn(px, py, self:segmentRect(i)) then return i end
    end
end

--- wraps past either end; onChange fires only on a real change
---@param index integer
function TabBar:setIndex(index)
    local count = #self.tabs
    if not self:isInteractive() or count == 0 then return end
    index = Math.wrapIndex(index, count)
    if index == self.index then return end
    self.index = index
    if self.onChange then self.onChange(self.tabs[index], index) end
end

---@param direction -1|1
function TabBar:adjust(direction)
    self:setIndex(self.index + direction)
end

function TabBar:activate()
    self:adjust(1)
end

---@return boolean captured # always false, a tab bar has no drag
function TabBar:mousepressed(px, py, mouseButton)
    if mouseButton == 1 and self:isInteractive() then
        local i = self:segmentAt(px, py)
        if i then self:setIndex(i) end
    end
    return false
end

function TabBar:mousemoved(px, py)
    self.hovered = self:isInteractive() and self:segmentAt(px, py) or nil
end

--- eases the highlight toward the active segment, so a switch slides
---@param dt number
function TabBar:update(dt)
    Widget.update(self, dt)
    self.highlight = Theme.approach(self.highlight, self.index, dt)
end

--- every segment, then the sliding highlight, then the labels on top
function TabBar:draw()
    local c, m = Theme.colors, Theme.metrics
    local alpha, radius = self:alpha(), m.radius

    for i = 1, #self.tabs do
        local x, y, w, h = self:segmentRect(i)
        Theme.setColor(c.panel, alpha)
        love.graphics.rectangle("fill", x, y, w, h, radius, radius, 8)
        Theme.setColor(c.panelBorder, alpha)
        love.graphics.rectangle("line", x, y, w, h, radius, radius, 8)
    end

    local hx, hy, hw, hh = self:segmentRect(self.highlight)
    if self.glow > 0.01 then
        Theme.glowRect(hx, hy, hw, hh, radius, self.glow * Theme.pulse(self.time), nil, true)
    end
    Theme.setColor(c.accentDark, alpha)
    love.graphics.rectangle("fill", hx, hy, hw, hh, radius, radius, 8)
    Theme.setColor(c.accent, alpha)
    love.graphics.rectangle("line", hx, hy, hw, hh, radius, radius, 8)

    local font = self:getFont()
    Theme.pushFont(font)
    for i, name in ipairs(self.tabs) do
        local x, y, w, h = self:segmentRect(i)
        local text = Theme.resolveLabel(name, self)
        local _, lines = font:getWrap(text, w)
        Theme.setColor((i == self.index or i == self.hovered) and c.text or c.textDim, alpha)
        love.graphics.printf(text, x, y + (h - #lines * font:getHeight()) / 2, w, "center")
    end
    Theme.popFont()

    love.graphics.setColor(1, 1, 1, 1)
end

return TabBar
