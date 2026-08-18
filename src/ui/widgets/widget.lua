-- The base every UI widget is built on. Button, Toggle, Slider, Selector,
-- and TabBar all declared the same fields and contains/labelText/update
-- bodies; this holds them once so each widget only writes what differs.
--
--   local Button = {}
--   Widget.extend(Button)
--   Button.fontRole = "button"
--
--   function Button.new(config)
--       local self = Widget.new(Button, config)
--       self.onSelect = config.onSelect
--       return self
--   end
--
-- The contract a widget presents to a FocusGroup:
--
--   required : contains(x, y)  update(dt)  draw()  enabled
--   optional : activate()      -- Enter / click
--              adjust(dir)     -- Left/Right, dir is -1 or 1
--              mousepressed(x, y, button) -> true to capture the mouse
--              mousemoved(x, y)
--              mousereleased(x, y, button)

local Theme = require "ui.core.theme"

local Widget = {}
Widget.__index = Widget

Widget.fontRole = "body" -- overridden per class (see Button/TabBar)

-- lookup goes instance -> class -> Widget, so a class table only carries its own overrides
function Widget.extend(class)
    class.__index = class
    return setmetatable(class, { __index = Widget })
end

function Widget.new(class, config)
    return setmetatable({
        label   = config.label or "",      -- string, or function(self) -> string
        enabled = config.enabled ~= false, -- disabled = greyed out and inert
        danger = config.danger or false,   -- lights up red instead of accent (Quit, Discard)
        font = config.font,                -- stored unresolved (nil, a role name, or a Font); see Widget:getFont
        x = config.x or 0,
        y = config.y or 0,
        w = config.w or 260,
        h = config.h or Theme.metrics.rowHeight,
        focused = false,
        glow = 0, -- eased 0..1 toward the focused look
        time = 0, -- drives the focused pulse
    }, class)
end

-- set by a layout pass (see each screen's layout()), never during draw
function Widget:setBounds(x, y, w, h)
    self.x, self.y, self.w, self.h = x, y, w, h
end

function Widget:contains(px, py)
    return Theme.pointIn(px, py, self.x, self.y, self.w, self.h)
end

function Widget:isInteractive()
    return self.enabled
end

function Widget:labelText()
    return Theme.resolveLabel(self.label, self)
end

-- resolved per draw, not in the constructor, so a Theme.rescale is picked up without rebuilding
function Widget:getFont()
    return Theme.fontFor(self.font, self.fontRole)
end

function Widget:alpha()
    return self.enabled and 1 or 0.4
end

-- overridden by widgets with a second reason to glow (a Slider stays lit for the length of a drag)
function Widget:isLit()
    return self.focused
end

-- default: a left-click inside the row activates it; returns false, only a
-- widget with a drag (Slider) captures the mouse
function Widget:mousepressed(px, py, mouseButton)
    if mouseButton == 1 and self:contains(px, py) and self.activate then
        self:activate()
    end
    return false
end

function Widget:drawRow(alpha)
    Theme.rowChrome(self.x, self.y, self.w, self.h, self.glow, self.time,
        alpha or self:alpha(), self.danger and "danger" or "accent")
end

-- caller owns the font stack, since most rows reuse the pushed font for a value column afterwards
function Widget:drawLabel(font, alpha)
    Theme.setColor(Theme.colors.text, alpha)
    love.graphics.print(self:labelText(), self.x + Theme.metrics.padding,
        Theme.centerY(self.y, self.h, font))
end

function Widget:update(dt)
    self.time = self.time + dt
    local lit = self:isLit() and self:isInteractive()
    self.glow = Theme.approach(self.glow, lit and 1 or 0, dt)
end

return Widget
