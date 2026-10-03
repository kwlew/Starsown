--- The base every UI widget is built on: the shared fields, focus easing,
-- hit-testing and the row background, so each widget only writes what
-- differs.
--
--   local Button = Widget.extend({})
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
--   required : contains(x, y)  update(dt)  draw()  isInteractive()
--   optional : activate()      -- Enter / click
--              adjust(dir)     -- Left/Right, dir is -1 or 1
--              mousepressed(x, y, button) -> true to capture the mouse
--              mousemoved(x, y)
--              mousereleased(x, y, button)
--
-- Settings rows also answer preferredControlSize(available) and get a
-- measured label/control layout from measureRow (see RowLayout).

local Theme = require("ui.core.theme")
local RowLayout = require("ui.layout.rowLayout")

local Widget = {}
Widget.__index = Widget

Widget.fontRole = "body" -- overridden per class

--- `primary` (Play) is tinted at rest, not lit -- the bloom stays reserved
-- for actual focus, so lighting up still reads as a change
Widget.PRIMARY_BASE_GLOW = 0.3

local DISABLED_ALPHA = 0.4

--- lookup goes instance -> class -> parent, so a class only carries its overrides
---@param class table # the subclass table
---@param parent? table # defaults to Widget
---@return table class
function Widget.extend(class, parent)
    class.__index = class
    return setmetatable(class, { __index = parent or Widget })
end

---@param class table
---@param config table # { label?: string|fun(self: table): string, enabled?: boolean, readOnly?: boolean, danger?: boolean, primary?: boolean, font?: love.Font|string, x?: number, y?: number, w?: number, h?: number }
---@return table
function Widget.new(class, config)
    return setmetatable({
        label    = config.label or "",       -- string, or function(self) -> string
        enabled  = config.enabled ~= false,  -- disabled = greyed out and inert
        readOnly = config.readOnly or false, -- shows its value, takes no input, not dimmed
        danger   = config.danger or false,   -- lights up red instead of accent (Quit, Discard)
        primary  = config.primary or false,  -- tinted at rest, not just while focused (Play)
        font     = config.font,              -- unresolved: nil, a role name, or a Font; see getFont
        x = config.x or 0,
        y = config.y or 0,
        w = config.w or 260,
        h = config.h or Theme.metrics.rowHeight,
        focused = false,
        glow = 0,       -- eased 0..1 toward the focused look
        time = 0,       -- drives the focused pulse
        introAlpha = 1, -- eased by an entrance animation (see Intro)
        rowLayout = nil, -- set by measureRow, for settings rows
    }, class)
end

--- set by a layout pass, never during draw
---@param x number
---@param y number
---@param w number
---@param h number
function Widget:setBounds(x, y, w, h)
    self.x, self.y, self.w, self.h = x, y, w, h
end

---@param px number
---@param py number
---@return boolean
function Widget:contains(px, py)
    return Theme.pointIn(px, py, self.x, self.y, self.w, self.h)
end

---@return boolean # whether input and the lit look apply at all
function Widget:isInteractive()
    return self.enabled and not self.readOnly
end

---@return string
function Widget:labelText()
    return Theme.resolveLabel(self.label, self)
end

--- resolved per draw, so a Theme.rescale is picked up without rebuilding
---@return any # a love.Font
function Widget:getFont()
    return Theme.fontFor(self.font, self.fontRole)
end

---@return number # 0..1, folding in both the disabled dim and an entrance animation
function Widget:alpha()
    return (self.enabled and 1 or DISABLED_ALPHA) * self.introAlpha
end

--- overridden by widgets with a second reason to glow (a Slider mid-drag)
---@return boolean
function Widget:isLit()
    return self.focused
end

--- default: a left-click inside activates; only a widget with a drag
-- (Slider) returns true to capture the mouse
---@param px number
---@param py number
---@param mouseButton integer
---@return boolean captured
function Widget:mousepressed(px, py, mouseButton)
    if mouseButton == 1 and self:contains(px, py) and self.activate then
        self:activate()
    end
    return false
end

---@param width number
---@return number height
function Widget:measureRow(width)
    local layout, height = RowLayout.measure(self, width)
    self.rowLayout = layout
    return height
end

--- the control's screen rect from the measured layout
---@return number x
---@return number y
---@return number w
---@return number h
function Widget:controlRect()
    local r = self.rowLayout
    return self.x + r.x, self.y + r.y, r.w, r.h
end

--- the shared row background: glow, fill and border
---@param alpha? number # defaults to the widget's own
function Widget:drawRow(alpha)
    Theme.rowChrome(self.x, self.y, self.w, self.h, self.glow, self.time,
        alpha or self:alpha(), self.danger and "danger" or "accent",
        self.primary and Widget.PRIMARY_BASE_GLOW or nil, self.introAlpha)
end

--- the label on the row's left, or where measureRow put it. Uses the
-- current font, so the caller owns the font stack.
---@param font any # a love.Font, already pushed
---@param alpha number
function Widget:drawLabel(font, alpha)
    Theme.setColor(Theme.colors.text, alpha)
    local r = self.rowLayout
    if r then
        love.graphics.printf(self:labelText(), self.x + r.labelX, self.y + r.labelY, r.labelW, "left")
    else
        love.graphics.print(self:labelText(), self.x + Theme.metrics.padding,
            Theme.centerY(self.y, self.h, font))
    end
end

--- eases the focus glow; subclasses call this before their own easing
---@param dt number
function Widget:update(dt)
    self.time = self.time + dt
    local lit = self:isLit() and self:isInteractive()
    self.glow = Theme.approach(self.glow, lit and 1 or 0, dt)
end

return Widget
