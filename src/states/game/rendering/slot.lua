-- src/states/game/rendering/slot.lua
-- One inventory slot, shared by the hotbar and the inventory panel.

local Theme = require "ui.core.theme"
local Items = require "states.game.items"
local Palette = require "states.game.rendering.palette"
local Shape = require "states.game.rendering.shape"

local Slot = {}

Slot.SIZE = 44
Slot.GAP = 6

local ROUNDING = 4
local ICON_FRACTION = 0.3 -- icon radius, of the slot size
local SLOT_ALPHA = 0.6
local SELECT_WIDTH = 2

--- a stack's icon (a placeholder polygon) centered on (cx, cy)
---@param stack table
---@param cx number
---@param cy number
---@param size number
function Slot.drawIcon(stack, cx, cy, size)
    local spec = Items.get(stack.id)
    local radius = size * ICON_FRACTION

    love.graphics.setColor(Palette.items[spec.color])
    Shape.draw("fill", cx, cy, radius, spec.sides, spec.rotation)
    Theme.setColor(Palette.entity.Default.outline, 0.7)
    love.graphics.setLineWidth(2)
    Shape.draw("line", cx, cy, radius, spec.sides, spec.rotation)
    love.graphics.setLineWidth(1)
end

---@param stack table
---@param x number # slot's right edge
---@param y number # slot's bottom edge
local function drawCount(stack, x, y)
    local font = Theme.font("small")
    local text = tostring(stack.count)
    local tx, ty = x - font:getWidth(text) - Theme.px(4), y - font:getHeight() - Theme.px(1)

    Theme.pushFont(font)
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.print(text, tx + 1, ty + 1)
    Theme.setColor(Theme.colors.text)
    love.graphics.print(text, tx, ty)
    Theme.popFont()
end

---@param x number
---@param y number
---@param size number
---@param stack table?
---@param opts? { selected?: boolean, hovered?: boolean, label?: string }
function Slot.draw(x, y, size, stack, opts)
    opts = opts or {}
    local rounding = Theme.px(ROUNDING)

    Theme.setColor(Theme.colors.panel, SLOT_ALPHA)
    love.graphics.rectangle("fill", x, y, size, size, rounding)
    if opts.hovered then
        Theme.setColor(Theme.colors.accent, 0.18)
        love.graphics.rectangle("fill", x, y, size, size, rounding)
    end

    if opts.selected then
        Theme.setColor(Theme.colors.accent)
        love.graphics.setLineWidth(SELECT_WIDTH)
    else
        Theme.setColor(Theme.colors.panelBorder, 0.9)
    end
    love.graphics.rectangle("line", x, y, size, size, rounding)
    love.graphics.setLineWidth(1)

    if opts.label then
        local font = Theme.font("debug")
        Theme.pushFont(font)
        Theme.setColor(Theme.colors.textDim, 0.8)
        love.graphics.print(opts.label, x + Theme.px(4), y + Theme.px(2))
        Theme.popFont()
    end

    if stack then
        Slot.drawIcon(stack, x + size / 2, y + size / 2, size)
        if stack.count > 1 then drawCount(stack, x + size, y + size) end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return Slot
