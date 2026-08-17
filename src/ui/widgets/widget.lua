-- src/ui/widget.lua
-- The base every UI widget is built on. Button, Toggle, Slider, Selector, and
-- TabBar all declared the same fields (x/y/w/h, focused, glow, time, font,
-- label, enabled) and the same contains/labelText/update bodies; this holds
-- them once so each widget only writes what actually differs.
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
--
-- Everything in `required` comes from here, so a new widget only has to write
-- `draw` plus whichever of the optional verbs it supports.

local Theme = require "ui.core.theme"

local Widget = {}
Widget.__index = Widget

-- Theme font role used when a widget is built without an explicit font.
-- Overridden per class (see Button/TabBar).
Widget.fontRole = "body"

-- Wires `class` to inherit from Widget: lookup goes instance -> class ->
-- Widget, so a class table only carries its own overrides.
function Widget.extend(class)
    class.__index = class
    return setmetatable(class, { __index = Widget })
end

-- The instance table every widget shares. Widget classes call this from their
-- own `new` and then attach their own fields.
function Widget.new(class, config)
    return setmetatable({
        label   = config.label or "",      -- string, or function(self) -> string
        enabled = config.enabled ~= false, -- disabled = greyed out and inert
        -- Marks a row that destroys something (Quit, Discard). Purely visual:
        -- it lights up red instead of in the accent, so hovering "Quit" looks
        -- different from hovering "Back" before either label is read.
        danger = config.danger or false,
        -- Stored unresolved (nil, a role name, or a Font); see Widget:getFont.
        font = config.font,
        x = config.x or 0,
        y = config.y or 0,
        w = config.w or 260,
        h = config.h or Theme.metrics.rowHeight,
        focused = false,
        glow = 0, -- eased 0..1 toward the focused look
        time = 0, -- drives the focused pulse
    }, class)
end

-- Set by a layout pass (see each screen's layout()), never during draw.
function Widget:setBounds(x, y, w, h)
    self.x, self.y, self.w, self.h = x, y, w, h
end

function Widget:contains(px, py)
    return Theme.pointIn(px, py, self.x, self.y, self.w, self.h)
end

-- Can this widget take focus and respond to input right now?
function Widget:isInteractive()
    return self.enabled
end

function Widget:labelText()
    return Theme.resolveLabel(self.label, self)
end

-- Resolved per draw rather than in the constructor, so a Theme.rescale (window
-- resize / resolution change) is picked up without rebuilding the widget.
function Widget:getFont()
    return Theme.fontFor(self.font, self.fontRole)
end

-- Row alpha: disabled widgets render dimmed.
function Widget:alpha()
    return self.enabled and 1 or 0.4
end

-- Whether the focused look should be lit. Overridden by widgets with a second
-- reason to glow — a Slider stays lit for the length of a drag.
function Widget:isLit()
    return self.focused
end

-- Default click handling: a left-click inside the row activates it. Returns
-- false — only a widget with a drag (Slider) captures the mouse. Overridden by
-- widgets that route the click to a sub-control (Selector's chevrons, TabBar's
-- segments) or need a drag.
function Widget:mousepressed(px, py, mouseButton)
    if mouseButton == 1 and self:contains(px, py) and self.activate then
        self:activate()
    end
    return false
end

-- The standard interactive-row background. Every row widget opens its draw with
-- this. Disabled rows render dimmed and never glow (update forces glow to 0).
function Widget:drawRow(alpha)
    Theme.rowChrome(self.x, self.y, self.w, self.h, self.glow, self.time,
        alpha or self:alpha(), self.danger and "danger" or "accent")
end

-- Left-aligned row label at the standard padding, vertically centered. The
-- caller owns the font stack, since most rows reuse the pushed font for a value
-- column afterwards.
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
