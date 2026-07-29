-- lib/ui/button.lua
-- Themed rounded-rect button. Focus (keyboard) and hover (mouse) share one
-- `focused` flag; the visual eases toward the accent look with a soft glow.
--
--   local b = Button.new{ label = "Play", onSelect = function() ... end }
--   -- a FocusGroup (or the owning layout) sets b's bounds and routes input
--
-- Set b.enabled = false to grey it out and make it inert (ignores clicks and
-- Enter, never glows); a FocusGroup skips it when moving focus.

local Theme = require "lib.ui.theme"
local Widget = require "lib.ui.widget"

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

    -- Centered rather than left-aligned, so this doesn't use Widget:drawLabel.
    Theme.pushFont(font)
    Theme.setColor(Theme.colors.text, alpha)
    love.graphics.printf(self:labelText(), self.x,
        Theme.centerY(self.y, self.h, font), self.w, "center")
    Theme.popFont()

    love.graphics.setColor(1, 1, 1, 1)
end

return Button
