--- Horizontal segmented tab bar: equal-width clickable segments with an
-- animated sliding highlight under the active tab. Keyboard left/right (via
-- :adjust) or Enter (:activate, cycles) also switch tabs when focused.
--
--   local bar = TabBar.new{
--       tabs = { "General", "Graphics" },
--       index = 1,
--       onChange = function(name, index) ... end,
--   }
--
-- Sync the active tab without firing onChange by setting `bar.index` directly.

local Theme = require "ui.core.theme"
local Widget = require "ui.widgets.widget"

local TabBar = {}
Widget.extend(TabBar)

TabBar.fontRole = "button"

local SEGMENT_GAP = 6 -- design-space px, scaled through Theme.px at use

---@param config table # Widget.new's fields, plus tabs: (string|fun(self: table): string)[], index: integer, onChange: fun(name: string, index: integer)
---@return table
function TabBar.new(config)
    local self = Widget.new(TabBar, config)
    self.tabs = config.tabs or {}
    self.index = config.index or 1
    self.onChange = config.onChange
    self.highlight = self.index -- eased continuous position of the active marker
    self.hovered = nil          -- segment index under the cursor, or nil
    return self
end

---@param i integer
---@return number x
---@return number y
---@return number w
---@return number h
function TabBar:segmentRect(i)
    local count = #self.tabs
    local gap = Theme.px(SEGMENT_GAP)
    local segW = (self.w - gap * (count - 1)) / count
    return self.x + (i - 1) * (segW + gap), self.y, segW, self.h
end

--- wraps past either end; onChange fires only on a real change, so a screen
-- can sync by assigning `index` directly instead
---@param index integer
function TabBar:setIndex(index)
    if not self:isInteractive() then return end
    local count = #self.tabs
    index = (index - 1) % count + 1
    if index == self.index then return end
    self.index = index
    if self.onChange then
        self.onChange(self.tabs[index], index)
    end
end

---@param direction -1|1
function TabBar:adjust(direction)
    self:setIndex(self.index + direction)
end

--- Enter cycles forward
function TabBar:activate()
    self:adjust(1)
end

--- returns false: a tab bar has no drag, so it never captures the mouse
---@param px number
---@param py number
---@param mouseButton integer
---@return boolean # captured; always false
function TabBar:mousepressed(px, py, mouseButton)
    if mouseButton ~= 1 or not self:isInteractive() then return false end
    for i = 1, #self.tabs do
        local sx, sy, sw, sh = self:segmentRect(i)
        if Theme.pointIn(px, py, sx, sy, sw, sh) then
            self:setIndex(i)
            return false
        end
    end
    return false
end

---@param px number
---@param py number
function TabBar:mousemoved(px, py)
    self.hovered = nil
    if not self:isInteractive() then return end
    for i = 1, #self.tabs do
        local sx, sy, sw, sh = self:segmentRect(i)
        if Theme.pointIn(px, py, sx, sy, sw, sh) then
            self.hovered = i
            return
        end
    end
end

--- eases the highlight toward the active segment, so a switch slides
---@param dt number
function TabBar:update(dt)
    Widget.update(self, dt)
    self.highlight = Theme.approach(self.highlight, self.index, dt)
end

--- every segment, then the sliding highlight over the active one, then the labels
function TabBar:draw()
    local c, m = Theme.colors, Theme.metrics
    local alpha = self:alpha()

    for i = 1, #self.tabs do
        local sx, sy, sw, sh = self:segmentRect(i)
        love.graphics.setColor(c.panel)
        love.graphics.rectangle("fill", sx, sy, sw, sh, m.radius, m.radius, 8)
        Theme.setColor(c.panelBorder, alpha)
        love.graphics.rectangle("line", sx, sy, sw, sh, m.radius, m.radius, 8)
    end

    local x1 = self:segmentRect(1)
    local x2, _, segW, segH = self:segmentRect(2)
    local stride = (#self.tabs > 1) and (x2 - x1) or 0
    local hx = x1 + (self.highlight - 1) * stride

    if self.glow > 0.01 then
        Theme.glowRect(hx, self.y, segW, segH, m.radius, self.glow * Theme.pulse(self.time), nil, true)
    end
    love.graphics.setColor(c.accentDark)
    love.graphics.rectangle("fill", hx, self.y, segW, segH, m.radius, m.radius, 8)
    Theme.setColor(c.accent, alpha)
    love.graphics.rectangle("line", hx, self.y, segW, segH, m.radius, m.radius, 8)

    local font = self:getFont()
    Theme.pushFont(font)
    local textY = Theme.centerY(self.y, self.h, font)
    for i, name in ipairs(self.tabs) do
        local sx, _, sw = self:segmentRect(i)
        Theme.setColor((i == self.index or i == self.hovered) and c.text or c.textDim, alpha)
        love.graphics.printf(Theme.resolveLabel(name, self), sx, textY, sw, "center") -- tabs may be strings or functions
    end
    Theme.popFont()

    love.graphics.setColor(1, 1, 1, 1)
end

return TabBar
