--- The vertical scrollbar of a ScrollArea: its geometry, thumb drag and
-- drawing. Reads the area's viewport and scroll state, and scrolls it
-- through area:setScroll.

local Theme = require("ui.core.theme")

local Scrollbar = {}
Scrollbar.__index = Scrollbar

Scrollbar.WIDTH = 12   -- design px
local MIN_THUMB_H = 28 -- design px

---@param area table # a ScrollArea
---@return table
function Scrollbar.new(area)
    return setmetatable({ area = area, dragOffset = nil }, Scrollbar)
end

---@return boolean # whether there's anything to scroll
function Scrollbar:isShown()
    return self.area.maxScroll > 0
end

---@return boolean
function Scrollbar:isDragging()
    return self.dragOffset ~= nil
end

---@return number x
---@return number y
---@return number w
---@return number h
function Scrollbar:trackRect()
    local a, w = self.area, Theme.px(Scrollbar.WIDTH)
    return a.x + a.w - w, a.y, w, a.h
end

--- sized by how much of the content is visible
---@return number x
---@return number y
---@return number w
---@return number h
function Scrollbar:thumbRect()
    local a = self.area
    local x, y, w, h = self:trackRect()
    local thumbH = math.min(h, math.max(Theme.px(MIN_THUMB_H), h * h / math.max(h, a.contentHeight)))
    local top = a.maxScroll > 0 and a.scrollY / a.maxScroll * (h - thumbH) or 0
    return x, y + top, w, thumbH
end

---@param x number
---@param y number
---@return boolean
function Scrollbar:contains(x, y)
    return self:isShown() and Theme.pointIn(x, y, self:trackRect())
end

--- a press on the thumb grabs it where it was pressed; a press elsewhere on
-- the track jumps the thumb's centre there
---@return boolean captured
function Scrollbar:mousepressed(x, y, button)
    if button ~= 1 or not self:contains(x, y) then return false end
    local tx, ty, tw, th = self:thumbRect()
    self.dragOffset = Theme.pointIn(x, y, tx, ty, tw, th) and y - ty or th / 2
    self:mousemoved(x, y)
    return true
end

---@return boolean consumed
function Scrollbar:mousemoved(_, y)
    if not self.dragOffset then return false end
    local a = self.area
    local _, _, _, thumbH = self:thumbRect()
    local travel = a.h - thumbH
    if travel > 0 then
        a:setScroll((y - a.y - self.dragOffset) / travel * a.maxScroll)
    end
    return true
end

---@return boolean consumed
function Scrollbar:mousereleased(_, _, button)
    if button ~= 1 or not self.dragOffset then return false end
    self.dragOffset = nil
    return true
end

function Scrollbar:draw()
    if not self:isShown() then return end
    local c = Theme.colors
    Theme.setColor(c.track)
    love.graphics.rectangle("fill", self:trackRect())
    Theme.setColor(self:isDragging() and c.accent or c.knob)
    love.graphics.rectangle("fill", self:thumbRect())
end

return Scrollbar
