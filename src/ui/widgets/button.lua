-- Themed rounded-rect button. Focus (keyboard) and hover (mouse) share one
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

function Button.new(config)
    local self = Widget.new(Button, config)
    self.onSelect = config.onSelect
    return self
end

function Button:activate()
    if not self:isInteractive() then return end
    if self.onSelect then
        self.onSelect(self)
    end
end

function Button:draw()
    local alpha, font = self:alpha(), self:getFont()
    self:drawRow(alpha)

    Theme.pushFont(font) -- centered, not left-aligned, so this doesn't use Widget:drawLabel
    Theme.setColor(Theme.colors.text, alpha)
    love.graphics.printf(self:labelText(), self.x,
        Theme.centerY(self.y, self.h, font), self.w, "center")
    Theme.popFont()

    love.graphics.setColor(1, 1, 1, 1)
end

return Button
