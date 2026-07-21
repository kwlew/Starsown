-- lib/ui/button.lua
-- Themed rounded-rect button. Focus (keyboard) and hover (mouse) share one
-- `focused` flag; the visual eases toward the accent look with a soft glow.
--
--   local b = Button.new{ label = "Play", onSelect = function() ... end }
--   -- layout owner sets b.x/y/w/h, then: b:update(dt)  b:draw()
--   -- input: b:contains(x, y), b:activate(), b:mousepressed(x, y, button)

local Theme = require "lib.ui.theme"

local Button = {}
Button.__index = Button

function Button.new(config)
    return setmetatable({
        label = config.label or "",   -- string, or function(self) -> string
        onSelect = config.onSelect,
        font = config.font or Theme.font("body"),
        x = config.x or 0,
        y = config.y or 0,
        w = config.w or 260,
        h = config.h or Theme.metrics.rowHeight,
        focused = false,
        glow = 0, -- eased 0..1 toward `focused`
        time = 0, -- drives the focused pulse
    }, Button)
end

function Button:labelText()
    return Theme.resolveLabel(self.label, self)
end

function Button:contains(px, py)
    return Theme.pointIn(px, py, self.x, self.y, self.w, self.h)
end

function Button:activate()
    if self.onSelect then
        self.onSelect(self)
    end
end

function Button:mousepressed(px, py, mouseButton)
    if mouseButton == 1 and self:contains(px, py) then
        self:activate()
    end
end

function Button:update(dt)
    self.time = self.time + dt
    self.glow = Theme.approach(self.glow, self.focused and 1 or 0, dt)
end

function Button:draw()
    local c = Theme.colors

    Theme.rowChrome(self.x, self.y, self.w, self.h, self.glow, self.time)

    Theme.withFont(self.font, function()
        love.graphics.setColor(c.text)
        local textY = Theme.centerY(self.y, self.h, self.font)
        love.graphics.printf(self:labelText(), self.x, textY, self.w, "center")
    end)

    love.graphics.setColor(1, 1, 1, 1)
end

return Button
