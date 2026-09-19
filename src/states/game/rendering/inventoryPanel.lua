-- src/states/game/rendering/inventoryPanel.lua
-- The inventory window, opened with E: storage rows on top, the hotbar row
-- below a divider. Left click lifts/drops a whole stack; right click lifts
-- half a stack, or places one item at a time while holding one. Shift-click
-- sends a stack to the other side (hotbar <-> storage).

local Theme = require "ui.core.theme"
local I18n = require "core.i18n"
local UI = require "ui"
local Slot = require "states.game.rendering.slot"

local Panel = { open = false }

local PAD = 16
local HEADING_GAP = 10
local HOTBAR_GAP = 16
local SCRIM_ALPHA = 0.35
local PANEL_ALPHA = 0.9
local ROUNDING = 6

--- the held stack only exists while the panel is open
local held

---@param inventory table
---@return boolean open
function Panel.toggle(inventory)
    if Panel.open then Panel.close(inventory) else Panel.open = true end
    return Panel.open
end

--- closing hands whatever is held back to the inventory
function Panel.close(inventory)
    if held then
        inventory:add(held.id, held.count)
        held = nil
    end
    Panel.open = false
end

--- Window rect and every slot's position, in screen space.
---@param inventory table
local function layout(inventory)
    local size, gap = Theme.px(Slot.SIZE), Theme.px(Slot.GAP)
    local pad = Theme.px(PAD)
    local cols = inventory.hotbarSize
    local storage = inventory.size - inventory.hotbarSize
    local rows = math.ceil(storage / cols)

    local headingH = Theme.font("button"):getHeight() + Theme.px(HEADING_GAP)
    local gridW = cols * size + (cols - 1) * gap
    local hotbarGap = Theme.px(HOTBAR_GAP)
    local storageH = rows * size + (rows - 1) * gap
    local width = gridW + pad * 2
    local height = pad * 2 + headingH + storageH + hotbarGap + size
    local x = math.floor((love.graphics.getWidth() - width) / 2)
    local y = math.floor((love.graphics.getHeight() - height) / 2)

    local slots = {}
    local top = y + pad + headingH
    for i = 1, storage do
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        slots[inventory.hotbarSize + i] = { x = x + pad + col * (size + gap), y = top + row * (size + gap) }
    end
    local hotbarTop = top + storageH + hotbarGap
    for i = 1, inventory.hotbarSize do
        slots[i] = { x = x + pad + (i - 1) * (size + gap), y = hotbarTop }
    end

    return { x = x, y = y, w = width, h = height, pad = pad, size = size, slots = slots,
             dividerY = top + storageH + hotbarGap / 2 }
end

---@return integer? index
local function slotAt(box, mx, my)
    for index, pos in pairs(box.slots) do
        if mx >= pos.x and mx < pos.x + box.size and my >= pos.y and my < pos.y + box.size then
            return index
        end
    end
end

--- Clicks are consumed whenever the panel is open.
---@param inventory table
---@param mx number
---@param my number
---@param button integer
---@return boolean consumed
function Panel.mousepressed(inventory, mx, my, button)
    if not Panel.open then return false end
    local index = slotAt(layout(inventory), mx, my)
    if not index then return true end

    if (button == 1 or button == 2) and love.keyboard.isDown("lshift", "rshift") then
        inventory:quickMove(index)
        UI.Sfx.select()
    elseif button == 1 then
        if held then held = inventory:put(index, held) else held = inventory:take(index) end
        UI.Sfx.select()
    elseif button == 2 then
        if held then held = inventory:putOne(index, held) else held = inventory:takeHalf(index) end
        UI.Sfx.select()
    end
    return true
end

--- Minecraft-style hotbar swap: a number key pressed while hovering a slot
-- exchanges it with the matching hotbar slot - even when the hovered slot is
-- empty, which pulls that hotbar item out into it rather than requiring
-- something to swap out first.
---@param inventory table
---@param target integer # 1..hotbarSize, the pressed number
---@return boolean handled
function Panel.moveToSlot(inventory, target)
    if not Panel.open or held then return false end

    local hovered = slotAt(layout(inventory), love.mouse.getPosition())
    if not hovered or hovered == target then return false end
    if not inventory:get(hovered) and not inventory:get(target) then return false end -- nothing to move

    inventory:swap(hovered, target)
    UI.Sfx.select()
    return true
end

--- Screen-space; call outside the camera transform.
---@param inventory table
function Panel.draw(inventory)
    if not Panel.open then return end
    local box = layout(inventory)
    local mx, my = love.mouse.getPosition()
    local hovered = slotAt(box, mx, my)

    love.graphics.setColor(0, 0, 0, SCRIM_ALPHA)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())

    Theme.setColor(Theme.colors.panel, PANEL_ALPHA)
    love.graphics.rectangle("fill", box.x, box.y, box.w, box.h, Theme.px(ROUNDING))
    Theme.setColor(Theme.colors.panelBorder)
    love.graphics.rectangle("line", box.x, box.y, box.w, box.h, Theme.px(ROUNDING))

    Theme.pushFont(Theme.font("button"))
    Theme.setColor(Theme.colors.text)
    love.graphics.print(I18n.t("inventory.title"), box.x + box.pad, box.y + box.pad)
    Theme.popFont()

    Theme.setColor(Theme.colors.panelBorder, 0.6)
    love.graphics.line(box.x + box.pad, box.dividerY, box.x + box.w - box.pad, box.dividerY)

    for index, pos in pairs(box.slots) do
        Slot.draw(pos.x, pos.y, box.size, inventory:get(index), {
            hovered = index == hovered,
            selected = index == inventory.selected,
        })
    end

    if held then
        Slot.drawIcon(held, mx, my, box.size)
        if held.count > 1 then
            Theme.pushFont(Theme.font("small"))
            Theme.setColor(Theme.colors.text)
            love.graphics.print(tostring(held.count), mx + box.size * 0.2, my + box.size * 0.05)
            Theme.popFont()
        end
    elseif hovered and inventory:get(hovered) then
        local name = I18n.t("items." .. inventory:get(hovered).id)
        local font = Theme.font("small")
        local pad = Theme.px(6)
        local w, h = font:getWidth(name) + pad * 2, font:getHeight() + pad
        local tx, ty = mx + Theme.px(14), my + Theme.px(14)

        Theme.setColor(Theme.colors.panel, 0.95)
        love.graphics.rectangle("fill", tx, ty, w, h, Theme.px(3))
        Theme.setColor(Theme.colors.panelBorder)
        love.graphics.rectangle("line", tx, ty, w, h, Theme.px(3))
        Theme.pushFont(font)
        Theme.setColor(Theme.colors.text)
        love.graphics.print(name, tx + pad, ty + pad / 2)
        Theme.popFont()
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return Panel
