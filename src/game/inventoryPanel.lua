-- The inventory grid. Click a slot to lift its stack onto the cursor, click
-- another to drop it -- merging onto a matching stack, swapping otherwise.
-- Right click splits a stack in half, and places one at a time.
--
-- The held stack lives here rather than in the Inventory, because it only
-- exists while this panel is open: closing puts it back (see close()), so
-- there is no way to walk away holding something that belongs in a slot.

local Theme = require "ui.core.theme"
local Items = require "game.items"
local Shape = require "game.shape"
local Label = require "ui.text.label"
local I18n = require "core.i18n"

local Panel = {}
Panel.__index = Panel

local COLS, ROWS = 6, 4

-- design-space px, all scaled through Theme.px at use
local SLOT = 46
local SLOT_GAP = 6
local PAD = 18
local TITLE_GAP = 12
local ICON_RATIO = 0.30 -- of the slot, so an icon never touches its border
local COUNT_INSET = 4
local HELD_RATIO = 0.34
-- the count sits over the corner of its own icon, so it needs an outline
-- rather than a drop shadow: a pale item and a pale digit look identical
local COUNT_OUTLINE = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }

function Panel.new(inventory)
    local self = setmetatable({
        inventory = inventory,
        open = false,
        held = nil,   -- the stack on the cursor, if any
        hovered = nil, -- slot index under the pointer
        bounds = { x = 0, y = 0, w = 0, h = 0 },
    }, Panel)
    self:layout()
    return self
end

function Panel:isOpen()
    return self.open
end

function Panel:openPanel()
    self.open = true
    self:layout()
end

-- whatever is on the cursor goes back in the bag; it came out of these slots,
-- so there is always room for it
function Panel:close()
    if self.held then
        self.inventory:add(self.held.id, self.held.count)
        self.held = nil
    end
    self.open = false
    self.hovered = nil
end

function Panel:slots()
    return COLS * ROWS
end

function Panel:layout()
    local slot, gap, pad = Theme.px(SLOT), Theme.px(SLOT_GAP), Theme.px(PAD)
    local titleHeight = Theme.font("button"):getHeight() + Theme.px(TITLE_GAP)

    local bounds = self.bounds
    bounds.w = COLS * slot + (COLS - 1) * gap + pad * 2
    bounds.h = ROWS * slot + (ROWS - 1) * gap + pad * 2 + titleHeight
    bounds.x = (love.graphics.getWidth() - bounds.w) / 2
    bounds.y = (love.graphics.getHeight() - bounds.h) / 2
    self.gridY = bounds.y + pad + titleHeight
end

-- top-left of a slot, in screen space
function Panel:slotOrigin(index)
    local slot, gap, pad = Theme.px(SLOT), Theme.px(SLOT_GAP), Theme.px(PAD)
    local col = (index - 1) % COLS
    local row = math.floor((index - 1) / COLS)
    return self.bounds.x + pad + col * (slot + gap), self.gridY + row * (slot + gap)
end

function Panel:slotAt(x, y)
    local size = Theme.px(SLOT)
    for index = 1, self:slots() do
        local sx, sy = self:slotOrigin(index)
        if Theme.pointIn(x, y, sx, sy, size, size) then return index end
    end
    return nil
end

function Panel:mousemoved(x, y)
    self.hovered = self:slotAt(x, y)
end

function Panel:mousepressed(x, y, button)
    local index = self:slotAt(x, y)
    self.hovered = index
    if not index then return false end

    local bag = self.inventory
    if button == 2 then
        self.held = self.held and bag:putOne(index, self.held) or bag:takeHalf(index)
    elseif button == 1 then
        self.held = self.held and bag:put(index, self.held) or bag:take(index)
    end
    return true
end

function Panel:hovering(x, y)
    return Theme.pointIn(x, y, self.bounds.x, self.bounds.y, self.bounds.w, self.bounds.h)
end

-- `corner` is the half-width of the box the count tucks into: the slot for a
-- stack in the grid, and a little past the icon for the one on the cursor.
-- Anchoring it to the icon instead puts the digits on top of the icon.
local function drawStack(stack, x, y, radius, corner, font)
    love.graphics.setColor(Items.color(stack.id))
    Shape.draw("fill", x, y, radius, Items.sides(stack.id))
    if stack.count <= 1 then return end

    local text = tostring(stack.count)
    local inset = Theme.px(COUNT_INSET)
    local textX = x + corner - font:getWidth(text) - inset
    local textY = y + corner - font:getHeight() - inset

    Theme.pushFont(font)
    Theme.setColor(Theme.colors.bg, 1)
    for _, offset in ipairs(COUNT_OUTLINE) do
        love.graphics.print(text, textX + offset[1], textY + offset[2])
    end
    Theme.setColor(Theme.colors.text)
    love.graphics.print(text, textX, textY)
    Theme.popFont()
end

function Panel:draw()
    local colors = Theme.colors
    local bounds = self.bounds
    local size = Theme.px(SLOT)
    local font = Theme.font("small")

    Theme.setColor(colors.scrim)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())
    Theme.panel(bounds.x, bounds.y, bounds.w, bounds.h)

    Label.draw{
        text = I18n.t("game.inventory.title"),
        x = bounds.x, y = bounds.y + Theme.px(PAD), width = bounds.w,
        font = Theme.font("button"),
    }

    for index = 1, self:slots() do
        local x, y = self:slotOrigin(index)
        local lit = self.hovered == index

        Theme.setColor(lit and colors.accentDark or colors.panelRaised)
        love.graphics.rectangle("fill", x, y, size, size, Theme.metrics.radius)
        Theme.setColor(lit and colors.accent or colors.panelBorder)
        love.graphics.rectangle("line", x, y, size, size, Theme.metrics.radius)

        local stack = self.inventory:get(index)
        if stack then
            drawStack(stack, x + size / 2, y + size / 2, size * ICON_RATIO, size / 2, font)
        end
    end

    if self.held then
        local x, y = love.mouse.getPosition()
        local radius = size * HELD_RATIO
        drawStack(self.held, x, y, radius, radius + Theme.px(COUNT_INSET) * 2, font)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return Panel
