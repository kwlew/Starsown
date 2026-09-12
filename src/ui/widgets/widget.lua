--- The base every UI widget is built on. Button, Toggle, Slider, Selector,
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

--- lookup goes instance -> class -> Widget, so a class table only carries its own overrides
---@param class table # the subclass table
---@return table class
function Widget.extend(class)
    class.__index = class
    return setmetatable(class, { __index = Widget })
end

--- the fields every widget shares; a subclass constructor adds only its own
---@param class table
---@param config table # { label?: string|fun(self: table): string, enabled?: boolean, danger?: boolean, primary?: boolean, font?: love.Font|string, x?: number, y?: number, w?: number, h?: number }
---@return table
function Widget.new(class, config)
    return setmetatable({
        label   = config.label or "",      -- string, or function(self) -> string
        enabled = config.enabled ~= false, -- disabled = greyed out and inert
        danger = config.danger or false,   -- lights up red instead of accent (Quit, Discard)
        primary = config.primary or false, -- always shows the lit look, not just while focused (Play)
        font = config.font,                -- stored unresolved (nil, a role name, or a Font); see Widget:getFont
        x = config.x or 0,
        y = config.y or 0,
        w = config.w or 260,
        h = config.h or Theme.metrics.rowHeight,
        focused = false,
        glow = 0, -- eased 0..1 toward the focused look
        time = 0, -- drives the focused pulse
        introAlpha = 1, -- eased 0..1 by an owner playing an entrance animation (see Menu:playIntro)
    }, class)
end

--- set by a layout pass (see each screen's layout()), never during draw
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

---@return string # the label, resolved if it's a function
function Widget:labelText()
    return Theme.resolveLabel(self.label, self)
end

--- resolved per draw, not in the constructor, so a Theme.rescale is picked up without rebuilding
---@return any # a love.Font
function Widget:getFont()
    return Theme.fontFor(self.font, self.fontRole)
end

---@return number # 0..1, folding in both the disabled dim and an entrance animation
function Widget:alpha()
    return (self.enabled and 1 or 0.4) * self.introAlpha
end

--- overridden by widgets with a second reason to glow (a Slider stays lit for the length of a drag)
---@return boolean
function Widget:isLit()
    return self.focused
end

--- `primary` (Play) is tinted at rest, not lit -- the bloom/full-brightness
-- look stays reserved for actual focus/hover, so lighting up on focus still
-- reads as a change instead of "a bit more of the same thing it always shows"
Widget.PRIMARY_BASE_GLOW = 0.5

--- default: a left-click inside the row activates it; returns false, only a
-- widget with a drag (Slider) captures the mouse
---@param px number
---@param py number
---@param mouseButton integer
---@return boolean # captured whether the widget wants further mouse events
function Widget:mousepressed(px, py, mouseButton)
    if mouseButton == 1 and self:contains(px, py) and self.activate then
        self:activate()
    end
    return false
end

--- the shared row background: glow, fill and border
---@param alpha? number # defaults to the widget's own
function Widget:drawRow(alpha)
    Theme.rowChrome(self.x, self.y, self.w, self.h, self.glow, self.time,
        alpha or self:alpha(), self.danger and "danger" or "accent",
        self.primary and Widget.PRIMARY_BASE_GLOW or nil)
end

--- Opt-in measured label/control layout, used by scrolling settings rows.
-- Relative rectangles survive scrolling without requiring another measure pass.
function Widget:measureRow(width)
    local m, font = Theme.metrics, self:getFont()
    local inner = math.max(1, width - m.padding * 2)
    local controlW, controlH = self:preferredControlSize(inner)
    controlW = math.min(inner, controlW)
    local stacked = font:getWidth(self:labelText()) + m.padding + controlW > inner
    local labelW = stacked and inner or math.max(1, inner - controlW - m.padding)
    local _, lines = font:getWrap(self:labelText(), labelW)
    local labelH = math.max(1, #lines) * font:getHeight()
    local vpad, gap = Theme.px(8), Theme.px(6)
    local height = math.max(m.rowHeight,
        (stacked and labelH + gap + controlH or math.max(labelH, controlH)) + vpad * 2)
    self.rowLayout = {
        labelX = m.padding, labelY = stacked and vpad or (height - labelH) / 2,
        labelW = labelW, labelH = labelH,
        x = width - m.padding - controlW,
        y = stacked and vpad + labelH + gap or (height - controlH) / 2,
        w = controlW, h = controlH, stacked = stacked,
    }
    return height
end

function Widget:controlRect()
    local r = self.rowLayout
    return self.x + r.x, self.y + r.y, r.w, r.h
end

--- caller owns the font stack
function Widget:drawLabel(font, alpha)
    Theme.setColor(Theme.colors.text, alpha)
    local r = self.rowLayout
    if r then
        love.graphics.printf(self:labelText(), self.x + r.labelX,
            self.y + r.labelY, r.labelW, "left")
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
