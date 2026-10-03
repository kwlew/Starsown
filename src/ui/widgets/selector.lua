--- Labelled discrete-option cycler: label on the left, "< value >" on the
-- right. Left/right step through the options; Enter steps forward. The whole
-- arrow+value+arrow cluster is one click target split down the middle --
-- left half back, right half forward -- so there's no thin chevron to miss.
--
--   local s = Selector.new{
--       label = "Resolution",
--       options = { {1280,720}, {1600,900}, {1920,1080} },
--       index = 1,
--       format = function(o) return o[1].."x"..o[2] end,
--       onChange = function(option, index) ... end,
--   }
--
-- Sync its display without firing onChange by setting `s.index` directly.

local Chevron = require("ui.icons.chevron")
local Math = require("utils.math")
local Theme = require("ui.core.theme")
local Widget = require("ui.widgets.widget")

local Selector = Widget.extend({})

local ARROW_W = 28      -- hit/draw width of each chevron
local VALUE_PAD = 16    -- breathing room either side of the widest value
local LABEL_MIN_W = 120 -- label space the value column may never eat into
local MIN_CONTROL_H = 28

---@param config table # Widget.new's fields, plus options: any[], index?: integer, format?: fun(option: any): string, onChange?: fun(option: any, index: integer), wrap?: boolean, valueWidth?: number
---@return table
function Selector.new(config)
    local self = Widget.new(Selector, config)
    self.options = config.options or {}
    self.index = config.index or 1
    self.format = config.format or tostring
    self.onChange = config.onChange
    self.wrap = config.wrap ~= false
    self.valueWidth = config.valueWidth or 190 -- design px floor; fits "1920x1080" at the body font
    self.hoverSide = 0 -- -1/1 for the half under the pointer, 0 for neither
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

--- valueWidth as a floor, grown to fit the widest formatted option -- what
-- keeps a long translation ("Pantalla Completa") the same size as a short one
---@param font any # a love.Font
---@return number
function Selector:widestValue(font)
    local width = Theme.px(self.valueWidth)
    for _, option in ipairs(self.options) do
        width = math.max(width, font:getWidth(self.format(option)) + Theme.px(VALUE_PAD))
    end
    return width
end

--- measures every value, so changing the selection never changes the row height
function Selector:preferredControlSize(available)
    local font = self:getFont()
    local arrows = Theme.px(ARROW_W) * 2
    local controlW = math.min(available, self:widestValue(font) + arrows)
    local valueW = math.max(1, controlW - arrows)
    local lines = 1
    for _, option in ipairs(self.options) do
        local _, wrapped = font:getWrap(self.format(option), valueW)
        lines = math.max(lines, #wrapped)
    end
    return controlW, math.max(Theme.px(MIN_CONTROL_H), lines * font:getHeight())
end

--- the whole arrow+value+arrow cluster
---@return number x
---@return number y
---@return number w
---@return number h
function Selector:controlBounds()
    if self.rowLayout then return self:controlRect() end
    local arrows = Theme.px(ARROW_W) * 2
    local available = self.w - Theme.metrics.padding * 2 - arrows - Theme.px(LABEL_MIN_W)
    local w = Math.clamp(self:widestValue(self:getFont()), 0, available) + arrows
    return self.x + self.w - Theme.metrics.padding - w, self.y, w, self.h
end

--- wraps or clamps per `wrap`; onChange fires only on a real change
---@param index integer
function Selector:setIndex(index)
    local count = #self.options
    if not self:isInteractive() or count == 0 then return end
    index = self.wrap and Math.wrapIndex(index, count) or Math.clamp(index, 1, count)
    if index == self.index then return end
    self.index = index
    if self.onChange then self.onChange(self.options[index], index) end
end

---@param direction -1|1
function Selector:adjust(direction)
    self:setIndex(self.index + direction)
end

function Selector:activate()
    self:adjust(1)
end

---@param px number
---@param py number
---@return integer # -1 for the left half of the cluster, 1 for the right, 0 outside it
function Selector:sideAt(px, py)
    local x, y, w, h = self:controlBounds()
    if not Theme.pointIn(px, py, x, y, w, h) then return 0 end
    return px < x + w / 2 and -1 or 1
end

---@param px number
---@param py number
---@param mouseButton integer
---@return boolean captured # always false, a selector has no drag
function Selector:mousepressed(px, py, mouseButton)
    if mouseButton == 1 then
        local side = self:sideAt(px, py)
        if side ~= 0 then self:adjust(side) end
    end
    return false
end

--- lights the chevron on the half under the pointer
---@param px number
---@param py number
function Selector:mousemoved(px, py)
    self.hoverSide = self:isInteractive() and self:sideAt(px, py) or 0
end

function Selector:draw()
    local c = Theme.colors
    local alpha, font = self:alpha(), self:getFont()
    self:drawRow(alpha)

    Theme.pushFont(font)
    self:drawLabel(font, alpha)

    local x, y, w, h = self:controlBounds()
    local arrowW = Theme.px(ARROW_W)
    if not self.readOnly then
        local live = self:isInteractive()
        for _, dir in ipairs({ -1, 1 }) do
            local lit = live and (self.focused or self.hoverSide == dir)
            Theme.setColor(lit and c.accent or c.textDim, alpha)
            Chevron.draw(dir < 0 and x or x + w - arrowW, y, arrowW, h, dir)
        end
    end

    -- a measured row wraps a long value; an unmeasured one scales it down as a last resort
    local text = self:displayText()
    local vx, vw = x + arrowW, w - arrowW * 2
    Theme.setColor(c.text, alpha)
    if self.rowLayout then
        local _, lines = font:getWrap(text, vw)
        love.graphics.printf(text, vx, y + (h - #lines * font:getHeight()) / 2, vw, "center")
    else
        local textW = font:getWidth(text)
        local scale = textW > 0 and math.min(1, vw / textW) or 1
        love.graphics.print(text, vx + (vw - textW * scale) / 2,
            y + (h - font:getHeight() * scale) / 2, 0, scale, scale)
    end
    Theme.popFont()

    love.graphics.setColor(1, 1, 1, 1)
end

return Selector
