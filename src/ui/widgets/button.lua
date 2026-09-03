--- Themed rounded-rect button. Focus (keyboard) and hover (mouse) share one
-- `focused` flag; the visual eases toward the accent look with a soft glow.
--
--   local b = Button.new{ label = "Play", onSelect = function() ... end }
--   -- a FocusGroup (or the owning layout) sets b's bounds and routes input
--
-- b.enabled = false greys it out and makes it inert.

local Theme = require "ui.core.theme"
local Widget = require "ui.widgets.widget"

local Button = {}
Widget.extend(Button)

Button.fontRole = "button"

---@param config table # Widget.new's fields, plus onSelect: fun(self: table)
---@return table
function Button.new(config)
    local self = Widget.new(Button, config)
    self.onSelect = config.onSelect
    self.textObject = nil
    self.textValue = nil
    self.textFont = nil
    self.textWidth = nil
    return self
end

--- fires onSelect, unless the button is disabled
function Button:activate()
    if not self:isInteractive() then return end
    if self.onSelect then
        self.onSelect(self)
    end
end

--- the row plus a centred label, its mesh rebuilt only when the text, font or
-- width actually changed
function Button:draw()
    local alpha, font = self:alpha(), self:getFont()
    self:drawRow(alpha)

    local label = self:labelText()
    if label ~= self.textValue or font ~= self.textFont or self.w ~= self.textWidth then
        self.textObject = love.graphics.newText(font)
        self.textObject:setf(label, self.w, "center")
        self.textValue = label
        self.textFont = font
        self.textWidth = self.w
    end

    Theme.setColor(Theme.colors.text, alpha)
    love.graphics.draw(self.textObject, self.x, Theme.centerY(self.y, self.h, font))

    love.graphics.setColor(1, 1, 1, 1)
end

return Button
