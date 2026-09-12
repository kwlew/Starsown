local Theme = require "ui.core.theme"
local Math = require "utils.math"
local Motion = require "ui.core.motion"

local SCROLL_SPEED = 18 -- about 170ms to cover 95% of the distance
local SETTLE_DISTANCE = 0.2

-- Owns content geometry and the scrollbar; the screen still owns focus/input.
local ScrollArea = {}
ScrollArea.__index = ScrollArea

function ScrollArea.new()
    return setmetatable({ offsets = {}, widgets = {}, scrollY = 0, targetY = 0, maxScroll = 0 }, ScrollArea)
end

function ScrollArea:contains(x, y)
    return Theme.pointIn(x, y, self.x, self.y, self.w, self.h)
end

function ScrollArea:allowsPointer(widget, x, y)
    if not self.offsets[widget] then return true end
    return self:contains(x, y) and x < self.x + self.rowWidth
end

function ScrollArea:layout(widgets, x, y, w, h, scrollY)
    self.widgets, self.x, self.y, self.w, self.h = widgets, x, y, w, h
    local function measure(width)
        self.offsets = {}
        local top = 0
        for _, widget in ipairs(widgets) do
            local headingH = 0
            if widget.section then
                local _, lines = Theme.font("help"):getWrap(Theme.resolveLabel(widget.section, widget), width)
                headingH = #lines * Theme.font("help"):getHeight() + Theme.px(8)
                top = top + headingH
            end
            local height = widget:measureRow(width)
            self.offsets[widget] = { y = top, h = height, headingH = headingH }
            top = top + height + Theme.metrics.rowGap
        end
        return math.max(0, top - Theme.metrics.rowGap)
    end
    self.rowWidth = w
    self.contentHeight = measure(w)
    if self.contentHeight > h then
        self.rowWidth = math.max(1, w - Theme.px(24))
        self.contentHeight = measure(self.rowWidth)
    end
    self.maxScroll = math.max(0, self.contentHeight - h)
    self:setScroll(scrollY or self.scrollY)
end

function ScrollArea:setScroll(value, smooth)
    self.targetY = Math.clamp(value, 0, self.maxScroll)
    if smooth and not Motion.reduced then return end
    self.scrollY = self.targetY
    self:positionRows()
end

function ScrollArea:update(dt)
    if self.scrollY == self.targetY then return end
    if Motion.reduced then return self:setScroll(self.targetY) end
    -- Exponential easing is independent of frame rate and cannot overshoot.
    self.scrollY = self.targetY + (self.scrollY - self.targetY) * math.exp(-SCROLL_SPEED * dt)
    if math.abs(self.scrollY - self.targetY) < SETTLE_DISTANCE then self.scrollY = self.targetY end
    self:positionRows()
end

function ScrollArea:positionRows()
    for _, widget in ipairs(self.widgets) do
        local row = self.offsets[widget]
        widget:setBounds(self.x, self.y + row.y - self.scrollY, self.rowWidth, row.h)
        -- A moved row must not keep a stale chevron hover state.
        if widget.mousemoved and not widget.dragging then
            widget:mousemoved(-math.huge, -math.huge)
        end
    end
end

function ScrollArea:reveal(widget, smooth)
    local row = self.offsets[widget]
    if not row then return end
    local destination = smooth and self.targetY or self.scrollY
    if row.y < destination then self:setScroll(row.y, smooth)
    elseif row.y + row.h > destination + self.h then
        self:setScroll(row.h > self.h and row.y or row.y + row.h - self.h, smooth)
    end
end

function ScrollArea:barRect()
    return self.x + self.w - Theme.px(12), self.y, Theme.px(12), self.h
end

function ScrollArea:thumbRect()
    local x, y, w, h = self:barRect()
    local thumbH = math.min(h, math.max(Theme.px(28), h * h / math.max(h, self.contentHeight)))
    local travel = h - thumbH
    local top = self.maxScroll > 0 and self.scrollY / self.maxScroll * travel or 0
    return x, y + top, w, thumbH
end

function ScrollArea:overBar(x, y)
    if self.maxScroll == 0 then return false end
    return Theme.pointIn(x, y, self:barRect())
end

function ScrollArea:mousepressed(x, y, button)
    if button ~= 1 or not self:overBar(x, y) then return false end
    local tx, ty, tw, th = self:thumbRect()
    if Theme.pointIn(x, y, tx, ty, tw, th) then
        self.dragOffset = y - ty
    else
        self.dragOffset = th / 2
    end
    self:mousemoved(x, y)
    return true
end

function ScrollArea:mousemoved(x, y)
    if not self.dragOffset then return false end
    local _, _, _, thumbH = self:thumbRect()
    local travel = self.h - thumbH
    if travel > 0 then
        self:setScroll((y - self.y - self.dragOffset) / travel * self.maxScroll)
    end
    return true
end

function ScrollArea:draw()
    love.graphics.push("all")
    love.graphics.intersectScissor(self.x, self.y, self.w, self.h)
    for _, widget in ipairs(self.widgets) do
        local row = self.offsets[widget]
        if widget.section then
            Theme.pushFont(Theme.font("help"))
            Theme.setColor(Theme.colors.textMuted)
            love.graphics.printf(Theme.resolveLabel(widget.section, widget), widget.x,
                widget.y - row.headingH, widget.w, "left")
            Theme.popFont()
        end
        if widget.y + widget.h > self.y and widget.y < self.y + self.h then widget:draw() end
    end
    if self.maxScroll > 0 then
        Theme.setColor(Theme.colors.track)
        love.graphics.rectangle("fill", self:barRect())
        Theme.setColor(self.dragOffset and Theme.colors.accent or Theme.colors.knob)
        love.graphics.rectangle("fill", self:thumbRect())
    end
    love.graphics.pop()
end

return ScrollArea
