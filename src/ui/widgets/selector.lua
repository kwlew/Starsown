--- Labeled discrete-option cycler: label on the left, "< value >" on the
-- right. Left/right arrows step through the options; Enter advances
-- forward. The mouse doesn't aim at the chevrons specifically -- the whole
-- arrow+value+arrow cluster is one click target split down the middle, left
-- half back, right half forward, so there's no thin sliver to miss.
--
--   local s = Selector.new{
--       label = "Resolution",
--       options = { {1280,720}, {1600,900}, {1920,1080} },
--       index = 1,                                    -- which option starts selected
--       format = function(o) return o[1].."x"..o[2] end,
--       onChange = function(option, index) ... end,   -- fired on every change
--   }
--
-- Sync its display without firing onChange by setting `s.index` directly.

local Theme = require "ui.core.theme"
local Widget = require "ui.widgets.widget"
local Math = require "utils.math"

local Selector = {}
Widget.extend(Selector)

local ARROW_W = 28    -- hit/draw width of each chevron
local ARROW_H = 8     -- half-height of the chevron triangle
local ARROW_BACK = 5  -- chevron's flat edge, from its center
local ARROW_TIP = 6   -- chevron's point, from its center
local VALUE_PAD = 16  -- breathing room either side of the widest value
local LABEL_MIN_W = 120 -- label space the value column may never eat into

---@param config table # Widget.new's fields, plus options: any[], index: integer, format: fun(option: any): string, onChange: fun(option: any, index: integer), wrap: boolean, valueWidth: number
---@return table
function Selector.new(config)
    local self = Widget.new(Selector, config)
    self.options = config.options or {}
    self.index = config.index or 1
    self.format = config.format or tostring
    self.onChange = config.onChange
    self.wrap = config.wrap ~= false
    self.valueWidth = config.valueWidth or 190 -- fits "1920x1080" at the body font
    self.hoverLeft = false
    self.hoverRight = false
    return self
end

---@return any|nil # the current option
function Selector:selected()
    return self.options[self.index]
end

---@return string # "--" when there are no options
function Selector:displayText()
    local option = self.options[self.index]
    if option == nil then return "--" end
    return self.format(option)
end

--- valueWidth as a floor, grown to fit the widest formatted option, capped so
-- the label always keeps LABEL_MIN_W. Sizing to content is what keeps a
-- long translation ("Pantalla Completa") the same size as a short one; the
-- draw-time down-scale is only a last resort for a row too narrow for even this.
---@param font any # a love.Font
---@return number
function Selector:valueColumnWidth(font)
    local m = Theme.metrics
    local width = Theme.px(self.valueWidth)
    for _, option in ipairs(self.options) do
        width = math.max(width, font:getWidth(self.format(option)) + Theme.px(VALUE_PAD))
    end
    local available = self.w - m.padding * 2 - Theme.px(ARROW_W) * 2 - Theme.px(LABEL_MIN_W)
    return Math.clamp(width, 0, available)
end

--- left chevron, value area, right chevron rects (for draw() positioning; see
-- controlBounds for the click/hover target, which doesn't follow these)
---@return table # left chevron rect
---@return table # value rect
---@return table # right chevron rect
function Selector:controlRects()
    local m = Theme.metrics
    local arrowW = Theme.px(ARROW_W)
    local valueW = self:valueColumnWidth(self:getFont())
    local rightArrowX = self.x + self.w - m.padding - arrowW
    local valueX = rightArrowX - valueW
    local leftArrowX = valueX - arrowW
    return
        { x = leftArrowX,  y = self.y, w = arrowW, h = self.h },
        { x = valueX,      y = self.y, w = valueW, h = self.h },
        { x = rightArrowX, y = self.y, w = arrowW, h = self.h }
end

--- the whole arrow+value+arrow cluster as one click target, split down the
-- middle rather than aiming at the chevrons themselves
---@return number x
---@return number y
---@return number w
---@return number h
function Selector:controlBounds()
    local left, _, right = self:controlRects()
    return left.x, self.y, (right.x + right.w) - left.x, self.h
end

--- wraps or clamps per `wrap`; onChange fires only on a real change, so a
-- screen can sync the display by assigning `index` directly instead
---@param index integer
function Selector:setIndex(index)
    if not self:isInteractive() then return end
    local count = #self.options
    if count == 0 then return end
    index = self.wrap and Math.wrapIndex(index, count) or Math.clamp(index, 1, count)
    if index == self.index then return end
    self.index = index
    if self.onChange then
        self.onChange(self.options[index], index)
    end
end

---@param direction -1|1
function Selector:adjust(direction)
    self:setIndex(self.index + direction)
end

--- Enter steps forward
function Selector:activate()
    self:adjust(1)
end

--- returns false: a selector has no drag, so it never captures the mouse
---@param px number
---@param py number
---@param mouseButton integer
---@return boolean # captured always false
function Selector:mousepressed(px, py, mouseButton)
    if mouseButton ~= 1 then return false end
    local x, y, w, h = self:controlBounds()
    if Theme.pointIn(px, py, x, y, w, h) then
        self:adjust(px < x + w / 2 and -1 or 1)
    end
    return false
end

--- tracks which half the pointer is over, so the matching chevron lights up
---@param px number
---@param py number
function Selector:mousemoved(px, py)
    if not self:isInteractive() then
        self.hoverLeft, self.hoverRight = false, false
        return
    end
    local x, y, w, h = self:controlBounds()
    local inside = Theme.pointIn(px, py, x, y, w, h)
    self.hoverLeft = inside and px < x + w / 2
    self.hoverRight = inside and not self.hoverLeft
end

---@param rect table
---@param dir -1|1
---@param active boolean # lit rather than dim
---@param alpha number
local function drawChevron(rect, dir, active, alpha)
    local cx = rect.x + rect.w / 2
    local cy = rect.y + rect.h / 2
    local half = Theme.px(ARROW_H)
    local back, tip = Theme.px(ARROW_BACK), Theme.px(ARROW_TIP)
    Theme.setColor(active and Theme.colors.accent or Theme.colors.textDim, alpha)
    if dir < 0 then
        love.graphics.polygon("fill", cx + back, cy - half, cx + back, cy + half, cx - tip, cy)
    else
        love.graphics.polygon("fill", cx - back, cy - half, cx - back, cy + half, cx + tip, cy)
    end
end

--- label left, chevrons and value right. The value scales down only if the
-- row is too narrow for even the reserved column.
function Selector:draw()
    local alpha, font = self:alpha(), self:getFont()
    self:drawRow(alpha)

    Theme.pushFont(font)
    self:drawLabel(font, alpha)

    local left, value, right = self:controlRects()
    local live = self:isInteractive()
    drawChevron(left, -1, live and (self.hoverLeft or self.focused), alpha)
    drawChevron(right, 1, live and (self.hoverRight or self.focused), alpha)
    Theme.setColor(Theme.colors.text, alpha)
    local vtext = self:displayText()
    local vw = font:getWidth(vtext)
    local scale = vw > 0 and math.min(1, value.w / vw) or 1
    local vx = value.x + (value.w - vw * scale) / 2
    local vy = self.y + (self.h - font:getHeight() * scale) / 2
    love.graphics.print(vtext, vx, vy, 0, scale, scale)

    Theme.popFont()
    love.graphics.setColor(1, 1, 1, 1)
end

return Selector
