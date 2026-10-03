--- Themed rounded-rect button. Focus (keyboard) and hover (mouse) share one
-- `focused` flag; the look eases toward the accent with a soft glow.
--
--   local b = Button.new{ label = "Play", icon = "play", onSelect = function() ... end }
--
-- An `icon` sits in a left column with a divider;
-- the label stays centred either way.

local Icon = require("ui.icons.icon")
local TextCache = require("ui.text.textCache")
local Theme = require("ui.core.theme")
local Widget = require("ui.widgets.widget")

local Button = Widget.extend({})

Button.fontRole = "button"

local ICON_SIZE = 0.46 -- of the row height
local DIVIDER_TOP, DIVIDER_BOTTOM = 0.28, 0.72 -- of the row height

---@param config table # Widget.new's fields, plus onSelect?: fun(self: table), icon?: string
---@return table
function Button.new(config)
    local self = Widget.new(Button, config)
    self.onSelect = config.onSelect
    self.icon = config.icon
    return self
end

--- fires onSelect, unless the button is inert
function Button:activate()
    if self:isInteractive() and self.onSelect then
        self.onSelect(self)
    end
end

---@return number # width of the icon column (0 without an icon); the label starts after it
function Button:iconColumn()
    return self.icon and self.h or 0
end

--- the icon, dim at rest and taking the row's accent as it lights up, then a
-- short divider between it and the label
---@param alpha number
function Button:drawIcon(alpha)
    local c = Theme.colors
    local column = self:iconColumn()
    local size = self.h * ICON_SIZE
    local lit = c[self.danger and "danger" or "accent"]
    local r, g, b = Theme.lerp(c.textMuted, lit, math.max(self.glow, self.primary and 1 or 0))
    love.graphics.setColor(r, g, b, alpha)
    Icon.draw(self.icon, self.x + (column - size) / 2, self.y + (self.h - size) / 2, size)

    Theme.setColor(c.textDim, 0.5 * alpha) -- not panelBorder: that vanishes into a lit row's fill
    love.graphics.setLineWidth(math.max(1, Theme.px(1)))
    local dx = self.x + column
    love.graphics.line(dx, self.y + self.h * DIVIDER_TOP, dx, self.y + self.h * DIVIDER_BOTTOM)
    love.graphics.setLineWidth(1)
end

--- centred on the whole button, clear of the icon;
-- too wide for that, centred beside the icon
---@param font any
---@param label string
---@return number x
---@return number w
function Button:labelArea(font, label)
    if not self.icon then return self.x, self.w end
    local inset = self:iconColumn() + Theme.metrics.padding
    local symmetric = self.w - inset * 2
    if font:getWidth(label) <= symmetric then return self.x + inset, symmetric end
    return self.x + inset, self.w - inset - Theme.metrics.padding
end

function Button:draw()
    local alpha, font = self:alpha(), self:getFont()
    self:drawRow(alpha)

    local label = self:labelText()
    local textX, textW = self:labelArea(font, label)
    local text = TextCache.get(label, font, textW, "center")

    if self.icon then self:drawIcon(alpha) end

    -- one line centres on its capitals (Theme.centerY); a wrapped label on its whole block
    local textY = text:getHeight() > font:getHeight()
        and self.y + (self.h - text:getHeight()) / 2
        or Theme.centerY(self.y, self.h, font)
    Theme.setColor(Theme.colors.text, alpha)
    love.graphics.draw(text, textX, textY)

    love.graphics.setColor(1, 1, 1, 1)
end

return Button
