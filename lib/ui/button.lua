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

-- Returns false: a button has no drag, so it never captures the mouse.
function Button:mousepressed(px, py, mouseButton)
    if mouseButton == 1 and self:contains(px, py) then
        self:activate()
    end
    return false
end

function Button:draw()
    local c = Theme.colors
    -- Disabled buttons render dimmed and never glow (update forces glow to 0).
    local alpha = self:alpha()
    local font = self:getFont()

    Theme.rowChrome(self.x, self.y, self.w, self.h, self.glow, self.time, alpha)

    Theme.pushFont(font)
    love.graphics.setColor(c.text[1], c.text[2], c.text[3], alpha)
    love.graphics.printf(self:labelText(), self.x,
        Theme.centerY(self.y, self.h, font), self.w, "center")
    Theme.popFont()

    love.graphics.setColor(1, 1, 1, 1)
end

return Button
