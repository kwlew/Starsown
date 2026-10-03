--- A clipped, scrolling column of settings rows. Owns where each row sits and
-- how far the column is scrolled; the screen still owns focus and input
-- routing (pass area:allowsPointer as the FocusGroup's pointerFilter).
--
--   area:layout(widgets, x, y, w, h)
--   group.pointerFilter = function(w, x, y) return area:allowsPointer(w, x, y) end
--   group.onFocusChanged = function(w) area:reveal(w, true) end
--
-- A widget with a `section` label gets a small heading drawn above it.

local Math = require("utils.math")
local Motion = require("ui.core.motion")
local Scrollbar = require("ui.widgets.scrollbar")
local Theme = require("ui.core.theme")

local ScrollArea = {}
ScrollArea.__index = ScrollArea

local SCROLL_SPEED = 18     -- exponential rate; about 170ms to cover 95% of the distance
local SETTLE_DISTANCE = 0.2 -- px; snaps the last fraction so it actually stops
local BOTTOM_PAD = 16       -- design px below the last row once scrolled all the way down
local BAR_GAP = 12          -- design px between the rows and the scrollbar
local SECTION_GAP = 8       -- design px between a section heading and its row
local SECTION_FONT = "help"
local WHEEL_STEP = 60       -- design px per wheel notch

local OFFSCREEN = -math.huge

---@return table
function ScrollArea.new()
    local self = setmetatable({
        widgets = {},
        offsets = {}, -- widget -> { y, h, headingH }, relative to the content top
        x = 0, y = 0, w = 0, h = 0,
        rowWidth = 0,
        contentHeight = 0,
        scrollY = 0,
        targetY = 0,
        maxScroll = 0,
    }, ScrollArea)
    self.scrollbar = Scrollbar.new(self)
    return self
end

---@param x number
---@param y number
---@return boolean
function ScrollArea:contains(x, y)
    return Theme.pointIn(x, y, self.x, self.y, self.w, self.h)
end

--- only the visible part of a row takes the pointer; widgets this area
-- doesn't own aren't its business
---@param widget table
---@param x number
---@param y number
---@return boolean
function ScrollArea:allowsPointer(widget, x, y)
    if not self.offsets[widget] then return true end
    return self:contains(x, y) and x < self.x + self.rowWidth
end

---@param widget table
---@return string|nil
local function sectionText(widget)
    return widget.section and Theme.resolveLabel(widget.section, widget)
end

--- stacks every row at `width`, measuring each; returns the content height
---@param width number
---@return number
function ScrollArea:measure(width)
    local font, gap = Theme.font(SECTION_FONT), Theme.metrics.rowGap
    self.offsets = {}
    local top = 0
    for _, widget in ipairs(self.widgets) do
        local headingH = 0
        local section = sectionText(widget)
        if section then
            local _, lines = font:getWrap(section, width)
            headingH = #lines * font:getHeight() + Theme.px(SECTION_GAP)
            top = top + headingH
        end
        local height = widget:measureRow(width)
        self.offsets[widget] = { y = top, h = height, headingH = headingH }
        top = top + height + gap
    end
    return math.max(0, top - gap) + Theme.px(BOTTOM_PAD)
end

--- measures the rows at full width, and again narrower if they overflow and
-- need room for the scrollbar. Call on build and on resize.
---@param widgets table[]
---@param x number
---@param y number
---@param w number
---@param h number
---@param scrollY? number # keeps the current scroll by default
function ScrollArea:layout(widgets, x, y, w, h, scrollY)
    self.widgets, self.x, self.y, self.w, self.h = widgets, x, y, w, h

    self.rowWidth = w
    self.contentHeight = self:measure(w)
    if self.contentHeight > h then
        self.rowWidth = math.max(1, w - Theme.px(Scrollbar.WIDTH + BAR_GAP))
        self.contentHeight = self:measure(self.rowWidth)
    end
    self.maxScroll = math.max(0, self.contentHeight - h)
    self:setScroll(scrollY or self.scrollY)
end

---@param value number
---@param smooth? boolean # ease there instead of jumping (ignored under reduced motion)
function ScrollArea:setScroll(value, smooth)
    self.targetY = Math.clamp(value, 0, self.maxScroll)
    if smooth and not Motion.reduced then return end
    self.scrollY = self.targetY
    self:positionRows()
end

--- scrolls just enough to bring `widget` fully into view
---@param widget table
---@param smooth? boolean
function ScrollArea:reveal(widget, smooth)
    local row = self.offsets[widget]
    if not row then return end
    local top = row.y - row.headingH -- keep its section heading with it
    local current = smooth and self.targetY or self.scrollY
    if top < current then
        self:setScroll(top, smooth)
    elseif row.y + row.h > current + self.h then
        self:setScroll(row.h > self.h and row.y or row.y + row.h - self.h, smooth)
    end
end

function ScrollArea:positionRows()
    for _, widget in ipairs(self.widgets) do
        local row = self.offsets[widget]
        widget:setBounds(self.x, self.y + row.y - self.scrollY, self.rowWidth, row.h)
        -- a row that moved under a still pointer mustn't keep a stale hover
        if widget.mousemoved and not widget.dragging then
            widget:mousemoved(OFFSCREEN, OFFSCREEN)
        end
    end
end

---@param dt number
function ScrollArea:update(dt)
    if self.scrollY == self.targetY then return end
    if Motion.reduced then return self:setScroll(self.targetY) end
    -- exponential easing: frame-rate independent and can't overshoot
    self.scrollY = self.targetY + (self.scrollY - self.targetY) * math.exp(-SCROLL_SPEED * dt)
    if math.abs(self.scrollY - self.targetY) < SETTLE_DISTANCE then self.scrollY = self.targetY end
    self:positionRows()
end

---@param dy number # love.wheelmoved's y; positive scrolls up
---@return boolean consumed
function ScrollArea:wheelmoved(dy)
    if self.maxScroll == 0 then return false end
    self:setScroll(self.targetY - dy * Theme.px(WHEEL_STEP), true)
    return true
end

---@return boolean captured
function ScrollArea:mousepressed(x, y, button)  return self.scrollbar:mousepressed(x, y, button)  end
---@return boolean consumed
function ScrollArea:mousemoved(x, y)            return self.scrollbar:mousemoved(x, y)            end
---@return boolean consumed
function ScrollArea:mousereleased(x, y, button) return self.scrollbar:mousereleased(x, y, button) end

---@param x number
---@param y number
---@return boolean # over the scrollbar, for the cursor's hover look
function ScrollArea:overScrollbar(x, y)
    return self.scrollbar:contains(x, y)
end

---@param widget table
---@param headingH number
local function drawSection(widget, headingH)
    Theme.pushFont(Theme.font(SECTION_FONT))
    Theme.setColor(Theme.colors.textMuted)
    love.graphics.printf(sectionText(widget), widget.x, widget.y - headingH, widget.w, "left")
    Theme.popFont()
end

--- the visible rows (and their headings) clipped to the area, then the scrollbar
function ScrollArea:draw()
    love.graphics.push("all")
    love.graphics.intersectScissor(self.x, self.y, self.w, self.h)
    for _, widget in ipairs(self.widgets) do
        local row = self.offsets[widget]
        local top = widget.y - row.headingH
        if widget.y + widget.h > self.y and top < self.y + self.h then
            if row.headingH > 0 then drawSection(widget, row.headingH) end
            widget:draw()
        end
    end
    self.scrollbar:draw()
    love.graphics.pop()
end

return ScrollArea
