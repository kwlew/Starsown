-- src/ui/tabBar.lua
-- Horizontal segmented tab bar: equal-width clickable segments with an
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

local Theme = require "ui.theme"
local Widget = require "ui.widget"

local TabBar = {}
Widget.extend(TabBar)

TabBar.fontRole = "button"

local SEGMENT_GAP = 6 -- design-space px, scaled through Theme.px at use

function TabBar.new(config)
    local self = Widget.new(TabBar, config)
    self.tabs = config.tabs or {}
    self.index = config.index or 1
    self.onChange = config.onChange
    self.highlight = self.index -- eased continuous position of the active marker
    self.hovered = nil          -- segment index under the cursor, or nil
    return self
end

function TabBar:segmentRect(i)
    local count = #self.tabs
    local gap = Theme.px(SEGMENT_GAP)
    local segW = (self.w - gap * (count - 1)) / count
    return self.x + (i - 1) * (segW + gap), self.y, segW, self.h
end

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

-- Keyboard left/right when focused.
function TabBar:adjust(direction)
    self:setIndex(self.index + direction)
end

-- Enter when focused: cycle to the next tab.
function TabBar:activate()
    self:adjust(1)
end

-- Returns false: a tab bar has no drag, so it never captures the mouse.
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

function TabBar:update(dt)
    Widget.update(self, dt)
    self.highlight = Theme.approach(self.highlight, self.index, dt)
end

function TabBar:draw()
    local c, m = Theme.colors, Theme.metrics
    local alpha = self:alpha()

    -- Inactive segment backgrounds.
    for i = 1, #self.tabs do
        local sx, sy, sw, sh = self:segmentRect(i)
        love.graphics.setColor(c.panel)
        love.graphics.rectangle("fill", sx, sy, sw, sh, m.radius, m.radius, 8)
        Theme.setColor(c.panelBorder, alpha)
        love.graphics.rectangle("line", sx, sy, sw, sh, m.radius, m.radius, 8)
    end

    -- Sliding active highlight, drawn at the eased position between segments.
    local x1 = self:segmentRect(1)
    local x2, _, segW, segH = self:segmentRect(2)
    local stride = (#self.tabs > 1) and (x2 - x1) or 0
    local hx = x1 + (self.highlight - 1) * stride

    if self.glow > 0.01 then
        Theme.glowRect(hx, self.y, segW, segH, m.radius, self.glow * Theme.pulse(self.time))
    end
    love.graphics.setColor(c.accentDark)
    love.graphics.rectangle("fill", hx, self.y, segW, segH, m.radius, m.radius, 8)
    Theme.setColor(c.accent, alpha)
    love.graphics.rectangle("line", hx, self.y, segW, segH, m.radius, m.radius, 8)

    -- Labels on top.
    local font = self:getFont()
    Theme.pushFont(font)
    local textY = Theme.centerY(self.y, self.h, font)
    for i, name in ipairs(self.tabs) do
        local sx, _, sw = self:segmentRect(i)
        Theme.setColor((i == self.index or i == self.hovered) and c.text or c.textDim, alpha)
        -- Tab entries may be plain strings or functions (for live-localized
        -- labels); resolve each at draw time.
        love.graphics.printf(Theme.resolveLabel(name, self), sx, textY, sw, "center")
    end
    Theme.popFont()

    love.graphics.setColor(1, 1, 1, 1)
end

return TabBar
