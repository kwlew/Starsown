-- lib/ui/tabBar.lua
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

local Theme = require "lib.ui.theme"

local TabBar = {}
TabBar.__index = TabBar

local SEGMENT_GAP = 6

function TabBar.new(config)
    local index = config.index or 1
    return setmetatable({
        tabs = config.tabs or {},
        index = index,
        onChange = config.onChange,
        font = config.font or Theme.font("body"),
        x = config.x or 0,
        y = config.y or 0,
        w = config.w or 260,
        h = config.h or Theme.metrics.rowHeight,
        focused = false,
        glow = 0,
        highlight = index, -- eased continuous position of the active marker
        hovered = nil,     -- segment index under the cursor, or nil
        time = 0,
    }, TabBar)
end

function TabBar:contains(px, py)
    return Theme.pointIn(px, py, self.x, self.y, self.w, self.h)
end

function TabBar:segmentRect(i)
    local count = #self.tabs
    local segW = (self.w - SEGMENT_GAP * (count - 1)) / count
    return self.x + (i - 1) * (segW + SEGMENT_GAP), self.y, segW, self.h
end

function TabBar:setIndex(index)
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

function TabBar:mousepressed(px, py, mouseButton)
    if mouseButton ~= 1 then return end
    for i = 1, #self.tabs do
        local sx, sy, sw, sh = self:segmentRect(i)
        if Theme.pointIn(px, py, sx, sy, sw, sh) then
            self:setIndex(i)
            return
        end
    end
end

function TabBar:mousemoved(px, py)
    self.hovered = nil
    for i = 1, #self.tabs do
        local sx, sy, sw, sh = self:segmentRect(i)
        if Theme.pointIn(px, py, sx, sy, sw, sh) then
            self.hovered = i
            return
        end
    end
end

function TabBar:update(dt)
    self.time = self.time + dt
    self.glow = Theme.approach(self.glow, self.focused and 1 or 0, dt)
    self.highlight = Theme.approach(self.highlight, self.index, dt)
end

function TabBar:draw()
    local c, m = Theme.colors, Theme.metrics

    -- Inactive segment backgrounds.
    for i = 1, #self.tabs do
        local sx, sy, sw, sh = self:segmentRect(i)
        love.graphics.setColor(c.panel)
        love.graphics.rectangle("fill", sx, sy, sw, sh, m.radius, m.radius, 8)
        love.graphics.setColor(c.panelBorder)
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
    love.graphics.setColor(c.accent)
    love.graphics.rectangle("line", hx, self.y, segW, segH, m.radius, m.radius, 8)

    -- Labels on top.
    local previousFont = love.graphics.getFont()
    love.graphics.setFont(self.font)
    local textY = Theme.centerY(self.y, self.h, self.font)
    for i, name in ipairs(self.tabs) do
        local sx, _, sw = self:segmentRect(i)
        if i == self.index or i == self.hovered then
            love.graphics.setColor(c.text)
        else
            love.graphics.setColor(c.textDim)
        end
        -- Tab entries may be plain strings or functions (for live-localized
        -- labels); resolve each at draw time.
        love.graphics.printf(Theme.resolveLabel(name, self), sx, textY, sw, "center")
    end
    love.graphics.setFont(previousFont)

    love.graphics.setColor(1, 1, 1, 1)
end

return TabBar
