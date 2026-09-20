-- src/states/game/rendering/inventoryPanel.lua
-- The inventory window, opened with E: storage rows on top, the hotbar row
-- below a divider. Left click lifts/drops a whole stack; right click lifts
-- half a stack, or places one item at a time while holding one. Shift-click
-- sends a stack to the other side (hotbar <-> storage).
-- Double-click a stack you just picked up to gather every matching item; hold a
-- stack and drag across slots to spread it (left: evenly, right: one each).
-- Opened with C it also shows a crafting grid above the storage: drag items in
-- and the matching recipe's result appears in the output slot.

local Theme = require "ui.core.theme"
local I18n = require "core.i18n"
local UI = require "ui"
local Slot = require "states.game.rendering.slot"
local Inventory = require "states.game.inventory"
local Items = require "states.game.items"
local Recipes = require "states.game.recipes"

local Panel = { open = false, crafting = false }

local PAD = 16
local HEADING_GAP = 10
local HOTBAR_GAP = 16
local SCRIM_ALPHA = 0.35
local PANEL_ALPHA = 0.9
local ROUNDING = 6
local DOUBLE_CLICK = 0.25 -- seconds

--- the held stack only exists while the panel is open
local held

--- a press with a stack in hand that may turn into a spread: { button, origin, slots }
-- where slots are { kind, index } the pointer has covered so far
local drag

--- where the last click lifted a stack from, for double-click
local lastPickup

--- the crafting grid is an inventory of its own, so it drags like any other
local grid = Inventory.new(Recipes.GRID * Recipes.GRID, Recipes.GRID * Recipes.GRID)

local function gridIds()
    local ids = {}
    for i = 1, grid.size do
        local stack = grid:get(i)
        ids[i] = stack and stack.id
    end
    return ids
end

--- moves a grid stack back into the inventory; whatever doesn't fit stays put
local function returnFromGrid(inventory, index)
    local stack = grid:take(index)
    if not stack then return end
    stack.count = inventory:add(stack.id, stack.count)
    if stack.count > 0 then grid:put(index, stack) end
end

local function returnGrid(inventory)
    for i = 1, grid.size do returnFromGrid(inventory, i) end
end

--- fresh run: nothing open, nothing held, nothing on the grid
function Panel.reset()
    Panel.open, Panel.crafting, held, drag, lastPickup = false, false, nil, nil, nil
    grid = Inventory.new(Recipes.GRID * Recipes.GRID, Recipes.GRID * Recipes.GRID)
end

--- pressing the key of the mode that's already showing closes it; the other
-- key switches modes
---@return boolean open
local function show(inventory, crafting)
    if Panel.open and Panel.crafting == crafting then
        Panel.close(inventory)
        return false
    end
    if not crafting then returnGrid(inventory) end
    Panel.open, Panel.crafting = true, crafting
    return true
end

---@param inventory table
---@return boolean open
function Panel.toggle(inventory) return show(inventory, false) end

---@param inventory table
---@return boolean open
function Panel.toggleCrafting(inventory) return show(inventory, true) end

--- closing hands whatever is held, and whatever sits on the grid, back to the inventory
function Panel.close(inventory)
    if held then
        inventory:add(held.id, held.count)
        held = nil
    end
    returnGrid(inventory)
    Panel.open, Panel.crafting, drag, lastPickup = false, false, nil, nil
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
    local craftSize = Recipes.GRID * size + (Recipes.GRID - 1) * gap
    local craftH = Panel.crafting and craftSize + hotbarGap or 0
    local width = gridW + pad * 2
    local height = pad * 2 + headingH + craftH + storageH + hotbarGap + size
    local x = math.floor((love.graphics.getWidth() - width) / 2)
    local y = math.floor((love.graphics.getHeight() - height) / 2)

    local slots, gridSlots, output, arrow = {}, {}, nil, nil
    local top = y + pad + headingH
    local craftDividerY
    if Panel.crafting then
        local blockW = craftSize + size * 2 -- grid, arrow, output
        local left = x + math.floor((width - blockW) / 2)
        for i = 1, grid.size do
            local col, row = (i - 1) % Recipes.GRID, math.floor((i - 1) / Recipes.GRID)
            gridSlots[i] = { x = left + col * (size + gap), y = top + row * (size + gap) }
        end
        arrow = { x = left + craftSize, y = top + craftSize / 2, w = size }
        output = { x = left + craftSize + size, y = top + (craftSize - size) / 2 }
        craftDividerY = top + craftSize + hotbarGap / 2
        top = top + craftH
    end
    for i = 1, storage do
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        slots[inventory.hotbarSize + i] = { x = x + pad + col * (size + gap), y = top + row * (size + gap) }
    end
    local hotbarTop = top + storageH + hotbarGap
    for i = 1, inventory.hotbarSize do
        slots[i] = { x = x + pad + (i - 1) * (size + gap), y = hotbarTop }
    end

    return { x = x, y = y, w = width, h = height, pad = pad, size = size, slots = slots,
             gridSlots = gridSlots, output = output, arrow = arrow, craftDividerY = craftDividerY,
             dividerY = top + storageH + hotbarGap / 2 }
end

local function inside(pos, size, mx, my)
    return mx >= pos.x and mx < pos.x + size and my >= pos.y and my < pos.y + size
end

--- what the point is over: an inventory slot, a grid slot, or the output
---@return string? kind # "inventory" | "grid" | "output"
---@return integer? index
local function slotAt(box, mx, my)
    for index, pos in pairs(box.slots) do
        if inside(pos, box.size, mx, my) then return "inventory", index end
    end
    for index, pos in pairs(box.gridSlots) do
        if inside(pos, box.size, mx, my) then return "grid", index end
    end
    if box.output and inside(box.output, box.size, mx, my) then return "output" end
end

---@param inventory table
---@param kind string
local function containerOf(inventory, kind)
    return kind == "grid" and grid or inventory
end

--- whether a slot holding `stack` can take more of `id`
local function canReceive(stack, id)
    return stack == nil or (stack.id == id and stack.count < Items.get(id).stack)
end

--- Plain click on a slot. Only ever called without shift.
local function clickSlot(inventory, button, kind, index)
    local target = containerOf(inventory, kind)
    lastPickup = nil
    if button == 1 then
        if held then
            held = target:put(index, held)
        else
            held = target:take(index)
            if held then lastPickup = { time = love.timer.getTime(), kind = kind, index = index } end
        end
    elseif held then
        held = target:putOne(index, held)
    else
        held = target:takeHalf(index)
    end
    UI.Sfx.select()
end

--- How much each spread slot would receive: left drag splits the stack evenly,
-- right drag gives one apiece; a slot never takes more than fits.
---@return integer[] amounts # parallel to d.slots
---@return integer total
local function spreadAmounts(inventory, d)
    local share = d.button == 1 and math.floor(held.count / #d.slots) or 1
    local max = Items.get(held.id).stack
    local amounts, total = {}, 0
    for i, slot in ipairs(d.slots) do
        local stack = containerOf(inventory, slot.kind):get(slot.index)
        amounts[i] = math.min(share, max - (stack and stack.count or 0))
        total = total + amounts[i]
    end
    return amounts, total
end

local function endDrag(inventory)
    local d = drag
    drag = nil
    if #d.slots < 2 then
        clickSlot(inventory, d.button, d.origin.kind, d.origin.index)
        return
    end

    local amounts, total = spreadAmounts(inventory, d)
    for i, slot in ipairs(d.slots) do
        local target = containerOf(inventory, slot.kind)
        local stack = target:get(slot.index)
        if stack then
            stack.count = stack.count + amounts[i]
        else
            target.slots[slot.index] = { id = held.id, count = amounts[i] }
        end
    end
    held.count = held.count - total
    if held.count <= 0 then held = nil end
    UI.Sfx.select()
end

--- Grows a pending spread as the pointer covers slots, and finishes it when the
-- button comes up. Call every frame.
---@param inventory table
function Panel.update(inventory)
    if not drag then return end
    if not held then drag = nil return end

    local kind, index = slotAt(layout(inventory), love.mouse.getPosition())
    if kind and index and kind ~= "output" and #drag.slots < held.count
        and canReceive(containerOf(inventory, kind):get(index), held.id) then
        local covered = false
        for _, slot in ipairs(drag.slots) do
            covered = covered or (slot.kind == kind and slot.index == index)
        end
        if not covered then drag.slots[#drag.slots + 1] = { kind = kind, index = index } end
    end

    if not love.mouse.isDown(drag.button) then endDrag(inventory) end
end

--- Takes one item from every occupied grid slot.
local function consumeGrid()
    for i = 1, grid.size do
        local stack = grid:get(i)
        if stack then
            stack.count = stack.count - 1
            if stack.count == 0 then grid.slots[i] = nil end
        end
    end
end

--- Crafts once onto the held stack (or into the hand, if empty-handed).
---@return boolean crafted
local function craftToHand(recipe)
    if held and (held.id ~= recipe.result or held.count + recipe.count > Items.get(recipe.result).stack) then
        return false
    end
    held = held or { id = recipe.result, count = 0 }
    held.count = held.count + recipe.count
    consumeGrid()
    return true
end

--- Crafts once straight into the inventory; nothing changes if it won't fit.
---@return boolean crafted
local function craftToInventory(inventory, recipe)
    local backup = inventory:snapshot()
    if inventory:add(recipe.result, recipe.count) > 0 then
        inventory:restore(backup)
        return false
    end
    consumeGrid()
    return true
end

---@param inventory table
---@param all boolean # shift-click: keep crafting until the ingredients or room run out
local function craft(inventory, all)
    local recipe = Recipes.match(gridIds())
    if not recipe then return end
    if not all then
        if craftToHand(recipe) then UI.Sfx.select() end
        return
    end
    local crafted = false
    while recipe and craftToInventory(inventory, recipe) do
        crafted = true
        recipe = Recipes.match(gridIds())
    end
    if crafted then UI.Sfx.select() end
end

--- Clicks are consumed whenever the panel is open.
---@param inventory table
---@param mx number
---@param my number
---@param button integer
---@return boolean consumed
function Panel.mousepressed(inventory, mx, my, button)
    if not Panel.open then return false end
    local kind, index = slotAt(layout(inventory), mx, my)
    if not (kind and index) then
        if kind == "output" and button == 1 then craft(inventory, love.keyboard.isDown("lshift", "rshift")) end
        return true
    end
    local shift = love.keyboard.isDown("lshift", "rshift")

    if (button ~= 1 and button ~= 2) then return true end
    if shift then
        if kind == "grid" then returnFromGrid(inventory, index) else inventory:quickMove(index) end
        UI.Sfx.select()
        return true
    end

    if not held then
        clickSlot(inventory, button, kind, index)
        return true
    end

    local last = lastPickup
    lastPickup = nil
    if button == 1 and last and last.kind == kind and last.index == index
        and love.timer.getTime() - last.time <= DOUBLE_CLICK then
        inventory:gather(held)
        grid:gather(held)
        UI.Sfx.select()
        return true
    end

    -- with a stack in hand the press waits: released on the same slot it is
    -- a plain click, dragged over more slots it becomes a spread
    drag = { button = button, origin = { kind = kind, index = index }, slots = {} }
    if canReceive(containerOf(inventory, kind):get(index), held.id) then
        drag.slots[1] = drag.origin
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

    local kind, hovered = slotAt(layout(inventory), love.mouse.getPosition())
    if kind ~= "inventory" or hovered == target then return false end
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
    local hoveredKind, hovered = slotAt(box, mx, my)
    local result = Panel.crafting and Recipes.match(gridIds())

    local preview, spent = {}, 0
    if drag and held and #drag.slots >= 2 then
        local amounts
        amounts, spent = spreadAmounts(inventory, drag)
        for i, slot in ipairs(drag.slots) do preview[slot.kind .. slot.index] = amounts[i] end
    end
    local function shown(kind, index, stack)
        local extra = preview[kind .. index]
        if not extra then return stack end
        return { id = held.id, count = (stack and stack.count or 0) + extra }
    end

    love.graphics.setColor(0, 0, 0, SCRIM_ALPHA)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())

    Theme.setColor(Theme.colors.panel, PANEL_ALPHA)
    love.graphics.rectangle("fill", box.x, box.y, box.w, box.h, Theme.px(ROUNDING))
    Theme.setColor(Theme.colors.panelBorder)
    love.graphics.rectangle("line", box.x, box.y, box.w, box.h, Theme.px(ROUNDING))

    Theme.pushFont(Theme.font("button"))
    Theme.setColor(Theme.colors.text)
    love.graphics.print(I18n.t(Panel.crafting and "crafting.title" or "inventory.title"), box.x + box.pad, box.y + box.pad)
    Theme.popFont()

    Theme.setColor(Theme.colors.panelBorder, 0.6)
    love.graphics.line(box.x + box.pad, box.dividerY, box.x + box.w - box.pad, box.dividerY)

    for index, pos in pairs(box.slots) do
        Slot.draw(pos.x, pos.y, box.size, shown("inventory", index, inventory:get(index)), {
            hovered = hoveredKind == "inventory" and index == hovered,
            selected = index == inventory.selected,
        })
    end

    local arrow, output = box.arrow, box.output
    if Panel.crafting and arrow and output then
        love.graphics.line(box.x + box.pad, box.craftDividerY, box.x + box.w - box.pad, box.craftDividerY)
        for index, pos in pairs(box.gridSlots) do
            Slot.draw(pos.x, pos.y, box.size, shown("grid", index, grid:get(index)), { hovered = hoveredKind == "grid" and index == hovered })
        end

        local a, half = arrow, box.size * 0.25
        Theme.setColor(Theme.colors.textDim)
        love.graphics.polygon("fill", a.x + a.w * 0.5 - half, a.y - half, a.x + a.w * 0.5 + half, a.y,
            a.x + a.w * 0.5 - half, a.y + half)
        Slot.draw(output.x, output.y, box.size, result and { id = result.result, count = result.count } or nil,
            { hovered = hoveredKind == "output" and result ~= nil })
    end

    local hoverId
    if hoveredKind == "output" then
        hoverId = result and result.result or nil
    elseif hoveredKind and hovered then
        local stack = (hoveredKind == "grid" and grid or inventory):get(hovered)
        hoverId = stack and stack.id
    end

    if held then
        local left = held.count - spent
        if left > 0 then
            Slot.drawIcon(held, mx, my, box.size)
            if left > 1 then
                Theme.pushFont(Theme.font("small"))
                Theme.setColor(Theme.colors.text)
                love.graphics.print(tostring(left), mx + box.size * 0.2, my + box.size * 0.05)
                Theme.popFont()
            end
        end
    elseif hoverId then
        local name = I18n.t("items." .. hoverId)
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
