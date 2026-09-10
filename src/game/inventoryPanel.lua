--- The inventory grid, plus a small column of equip slots beside it. Click a
-- slot to lift its stack onto the cursor, click another to drop it -- merging
-- onto a matching stack, swapping otherwise. Right click splits a stack in
-- half, and places one at a time.
--
-- The held stack lives here rather than in the Inventory, because it only
-- exists while this panel is open: closing puts it back (see close()), so
-- there is no way to walk away holding something that belongs in a slot.
--
-- Equip slots are a separate cluster, not a repurposing of the grid: each
-- one accepts only an item whose own `slot` field names it (see
-- game/items.lua), holds at most one, and reads/writes `equipped` directly
-- -- a live reference to Player.equipped, not a copy. `EQUIP_SLOTS` is the
-- one place their names are listed; adding a second slot (armor, say) later
-- is just another entry there plus an i18n label, no other change here.

local Theme = require "ui.core.theme"
local Items = require "game.items"
local Shape = require "game.shape"
local Label = require "ui.text.label"
local I18n = require "core.i18n"

local Panel = {}
Panel.__index = Panel

local COLS, ROWS = 6, 4
local EQUIP_SLOTS = { "weapon" }

local SLOT = 46
local SLOT_GAP = 6
local PAD = 18
local TITLE_GAP = 12
local EQUIP_GRID_GAP = 18 -- between the equip column and the main grid
local EQUIP_LABEL_GAP = 6 -- between an equip slot and its name below it
local ICON_RATIO = 0.30 -- of the slot, so an icon never touches its border
local COUNT_INSET = 4
local HELD_RATIO = 0.34
local COUNT_OUTLINE = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }

--- the shared row look every slot (bag or equip) draws with
---@param x number
---@param y number
---@param size number
---@param lit boolean|nil
local function drawSlotBox(x, y, size, lit)
    local colors = Theme.colors
    Theme.setColor(lit and colors.accentDark or colors.panelRaised)
    love.graphics.rectangle("fill", x, y, size, size, Theme.metrics.radius)
    Theme.setColor(lit and colors.accent or colors.panelBorder)
    love.graphics.rectangle("line", x, y, size, size, Theme.metrics.radius)
end

---@param inventory table # the Inventory it draws and edits
---@param equipped table # a live reference to Player.equipped: slot name -> item id, or nil
---@return table
function Panel.new(inventory, equipped)
    local self = setmetatable({
        inventory = inventory,
        equipped = equipped,
        open = false,
        held = nil,   -- the stack on the cursor, if any
        hovered = nil, -- { kind = "bag", index = n } or { kind = "equip", name = s }
        bounds = { x = 0, y = 0, w = 0, h = 0 },
    }, Panel)
    self:layout()
    return self
end

---@return boolean
function Panel:isOpen()
    return self.open
end

--- shows the grid, laid out for the current window
function Panel:openPanel()
    self.open = true
    self:layout()
end

--- whatever is on the cursor goes back in the bag; it came out of these slots
-- (or an equip slot, in which case add() is still fine -- an unequipped item
-- is a bag item again, same as InventoryPanel already treats it while held),
-- so there is always room for it
function Panel:close()
    if self.held then
        self.inventory:add(self.held.id, self.held.count)
        self.held = nil
    end
    self.open = false
    self.hovered = nil
end

---@return integer
function Panel:slots()
    return COLS * ROWS
end

--- centres the panel; call on open and on resize. The equip column sits to
-- the left of the grid, vertically centred against it.
function Panel:layout()
    local slot, gap, pad = Theme.px(SLOT), Theme.px(SLOT_GAP), Theme.px(PAD)
    local equipGap = Theme.px(EQUIP_GRID_GAP)
    local titleHeight = Theme.font("button"):getHeight() + Theme.px(TITLE_GAP)

    local gridW = COLS * slot + (COLS - 1) * gap
    local gridH = ROWS * slot + (ROWS - 1) * gap
    local equipH = #EQUIP_SLOTS * slot + (#EQUIP_SLOTS - 1) * gap

    local bounds = self.bounds
    bounds.w = slot + equipGap + gridW + pad * 2
    bounds.h = math.max(gridH, equipH) + pad * 2 + titleHeight
    bounds.x = (love.graphics.getWidth() - bounds.w) / 2
    bounds.y = (love.graphics.getHeight() - bounds.h) / 2

    self.gridY = bounds.y + pad + titleHeight
    self.gridX = bounds.x + pad + slot + equipGap
    self.equipX = bounds.x + pad
    self.equipY = self.gridY + (gridH - equipH) / 2
end

--- top-left of a bag slot, in screen space
---@param index integer # 1-based, row major
---@return number x
---@return number y
function Panel:slotOrigin(index)
    local slot, gap = Theme.px(SLOT), Theme.px(SLOT_GAP)
    local col = (index - 1) % COLS
    local row = math.floor((index - 1) / COLS)
    return self.gridX + col * (slot + gap), self.gridY + row * (slot + gap)
end

--- top-left of one equip slot, in screen space
---@param index integer # 1-based into EQUIP_SLOTS
---@return number x
---@return number y
function Panel:equipSlotOrigin(index)
    local slot, gap = Theme.px(SLOT), Theme.px(SLOT_GAP)
    return self.equipX, self.equipY + (index - 1) * (slot + gap)
end

---@param x number
---@param y number
---@return integer|nil
function Panel:slotAt(x, y)
    local size = Theme.px(SLOT)
    for index = 1, self:slots() do
        local sx, sy = self:slotOrigin(index)
        if Theme.pointIn(x, y, sx, sy, size, size) then return index end
    end
    return nil
end

---@param x number
---@param y number
---@return string|nil # an EQUIP_SLOTS name
function Panel:equipSlotAt(x, y)
    local size = Theme.px(SLOT)
    for index, name in ipairs(EQUIP_SLOTS) do
        local sx, sy = self:equipSlotOrigin(index)
        if Theme.pointIn(x, y, sx, sy, size, size) then return name end
    end
    return nil
end

---@param x number
---@param y number
---@return table|nil hit # { kind = "bag", index = n } or { kind = "equip", name = s }
function Panel:hitTest(x, y)
    local index = self:slotAt(x, y)
    if index then return { kind = "bag", index = index } end

    local name = self:equipSlotAt(x, y)
    if name then return { kind = "equip", name = name } end

    return nil
end

---@param x number
---@param y number
function Panel:mousemoved(x, y)
    self.hovered = self:hitTest(x, y)
end

--- swaps whatever's on the cursor with whatever's equipped in `name`. A held
-- stack is only accepted if it's a single unit of an item actually tagged
-- for this slot -- equipment doesn't stack, so anything else is refused
-- outright (the held stack comes back unchanged) rather than silently
-- dropping the extra units or equipping the wrong kind of item.
---@param name string # an EQUIP_SLOTS entry
---@param held table|nil # { id: string, count: integer }
---@return table|nil # the new held stack
function Panel:swapEquip(name, held)
    local equippedId = self.equipped[name]

    if held then
        if held.count ~= 1 or Items.slot(held.id) ~= name then return held end
        self.equipped[name] = held.id
        return equippedId and { id = equippedId, count = 1 } or nil
    end

    if not equippedId then return nil end
    self.equipped[name] = nil
    return { id = equippedId, count = 1 }
end

--- left click lifts or drops a whole stack, right click splits one in half and
-- then places one at a time. Bag slots go through Inventory's take/put pair;
-- equip slots go through swapEquip -- either way the cursor holds at most
-- one stack.
--
-- The `if self.held then ... else ... end` shape below matters: a plain
-- `self.held and bag:put(...) or bag:take(...)` looks equivalent but isn't
-- -- put()/putOne() both return `nil` on a fully successful placement (the
-- slot was empty, or the whole stack merged in), and `nil` is falsy, so the
-- `or` would silently fall through and take the stack right back off the
-- slot it was just dropped on.
---@param x number
---@param y number
---@param button integer
---@return boolean consumed
function Panel:mousepressed(x, y, button)
    local hit = self:hitTest(x, y)
    self.hovered = hit
    if not hit then return false end

    if hit.kind == "bag" then
        local bag = self.inventory
        if button == 2 then
            if self.held then self.held = bag:putOne(hit.index, self.held)
            else self.held = bag:takeHalf(hit.index) end
        elseif button == 1 then
            if self.held then self.held = bag:put(hit.index, self.held)
            else self.held = bag:take(hit.index) end
        end
    elseif hit.kind == "equip" and button == 1 then
        self.held = self:swapEquip(hit.name, self.held)
    end
    return true
end

---@param x number
---@param y number
---@return boolean # whether the point is over the panel at all
function Panel:hovering(x, y)
    return Theme.pointIn(x, y, self.bounds.x, self.bounds.y, self.bounds.w, self.bounds.h)
end

--- `corner` is the half-width of the box the count tucks into: the slot for a
-- stack in the grid, and a little past the icon for the one on the cursor.
-- Anchoring it to the icon instead puts the digits on top of the icon.
---@param stack table # { id: string, count: integer }
---@param x number # centre of the icon
---@param y number # centre of the icon
---@param radius number
---@param corner number # half-width of the box the count tucks into
---@param font any # a love.Font
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

--- scrim, panel, title, the equip column, the slot grid, and last the stack
-- on the cursor
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

    for index, name in ipairs(EQUIP_SLOTS) do
        local x, y = self:equipSlotOrigin(index)
        local lit = self.hovered and self.hovered.kind == "equip" and self.hovered.name == name
        drawSlotBox(x, y, size, lit)

        local equippedId = self.equipped[name]
        if equippedId then
            drawStack({ id = equippedId, count = 1 }, x + size / 2, y + size / 2, size * ICON_RATIO, size / 2, font)
        end

        Label.draw{
            text = I18n.t("game.inventory.slot." .. name),
            x = x, y = y + size + Theme.px(EQUIP_LABEL_GAP), width = size,
            align = "center", font = font, color = colors.textDim,
        }
    end

    for index = 1, self:slots() do
        local x, y = self:slotOrigin(index)
        local lit = self.hovered and self.hovered.kind == "bag" and self.hovered.index == index
        drawSlotBox(x, y, size, lit)

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
