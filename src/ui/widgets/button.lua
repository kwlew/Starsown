--- Themed rounded-rect button. Focus (keyboard) and hover (mouse) share one
-- `focused` flag; the visual eases toward the accent look with a soft glow.
--
--   local b = Button.new{ label = "Play", icon = "play", onSelect = function() ... end }
--   -- a FocusGroup (or the owning layout) sets b's bounds and routes input
--
-- b.enabled = false greys it out and makes it inert. With an `icon` (a
-- Glyph name) the label moves left, after an icon column and a divider;
-- without one it stays centred.

local Theme = require "ui.core.theme"
local Widget = require "ui.widgets.widget"
local Glyph = require "ui.icons.glyph"

local Button = {}
Widget.extend(Button)

Button.fontRole = "button"

local ICON_SIZE = 0.46 -- of the row height

---@param config table # Widget.new's fields, plus onSelect: fun(self: table), icon?: string
---@return table
function Button.new(config)
    local self = Widget.new(Button, config)
    self.onSelect = config.onSelect
    self.icon = config.icon
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

---@return number # width of the icon column (0 without an icon); the label starts after it
function Button:iconColumn()
    return self.icon and self.h or 0
end

--- the icon, dim at rest and taking the row's accent as it lights up, then a
-- short divider between it and the label
---@param alpha number
function Button:drawIcon(alpha)
    local column = self:iconColumn()
    local size = self.h * ICON_SIZE
    local lit = Theme.colors[self.danger and "danger" or "accent"]
    local r, g, b = Theme.lerp(Theme.colors.textMuted, lit, math.max(self.glow, self.primary and 1 or 0))
    love.graphics.setColor(r, g, b, alpha)
    Glyph.draw(self.icon, self.x + (column - size) / 2, self.y + (self.h - size) / 2, size)

    Theme.setColor(Theme.colors.textDim, 0.5 * alpha) -- not panelBorder: that vanishes into a lit row's fill
    local previous = love.graphics.getLineWidth()
    love.graphics.setLineWidth(math.max(1, Theme.px(1)))
    love.graphics.line(self.x + column, self.y + self.h * 0.28, self.x + column, self.y + self.h * 0.72)
    love.graphics.setLineWidth(previous)
end

--- the row, the icon if there is one, and the label -- its mesh rebuilt only
-- when the text, font or width actually changed
function Button:draw()
    local alpha, font = self:alpha(), self:getFont()
    self:drawRow(alpha)

    local column = self:iconColumn()
    local pad = self.icon and Theme.metrics.padding or 0
    local textW = self.w - column - pad * 2
    local label = self:labelText()
    if label ~= self.textValue or font ~= self.textFont or textW ~= self.textWidth then
        self.textObject = love.graphics.newText(font)
        self.textObject:setf(label, textW, self.icon and "left" or "center")
        self.textValue = label
        self.textFont = font
        self.textWidth = textW
    end

    if self.icon then self:drawIcon(alpha) end

    -- one line centres on its capitals (Theme.centerY); a wrapped label on its whole block
    local textY = self.textObject:getHeight() > font:getHeight()
        and self.y + (self.h - self.textObject:getHeight()) / 2
        or Theme.centerY(self.y, self.h, font)
    Theme.setColor(Theme.colors.text, alpha)
    love.graphics.draw(self.textObject, self.x + column + pad, textY)

    love.graphics.setColor(1, 1, 1, 1)
end

return Button
