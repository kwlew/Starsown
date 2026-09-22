-- src/states/game/inventory.lua
-- Inventory.

local Items = require "states.game.items"

local Inventory = {}
Inventory.__index = Inventory

---@param size integer
---@param hotbarSize integer
function Inventory.new(size, hotbarSize)
    return setmetatable({ size = size, hotbarSize = hotbarSize, slots = {}, selected = 1 }, Inventory)
end

---@param index integer
---@return table? stack
function Inventory:get(index)
    return self.slots[index]
end

--- the selected hotbar stack, if any
function Inventory:selectedStack()
    return self.slots[self.selected]
end

---@param index integer # wraps around the hotbar
function Inventory:select(index)
    self.selected = (index - 1) % self.hotbarSize + 1
end

--- lifts the whole stack out of a slot
---@param index integer
---@return table? stack
function Inventory:take(index)
    local stack = self.slots[index]
    self.slots[index] = nil
    return stack
end

--- drops `stack` into a slot: merges into a matching stack (returning what
-- didn't fit), otherwise swaps and returns the displaced stack
---@param index integer
---@param stack table
---@return table? leftover
function Inventory:put(index, stack)
    local current = self.slots[index]
    if current and current.id == stack.id then
        local moved = math.min(Items.get(stack.id).stack - current.count, stack.count)
        current.count = current.count + moved
        stack.count = stack.count - moved
        return stack.count > 0 and stack or nil
    end
    self.slots[index] = stack
    return current
end

--- lifts the larger half of a slot's stack
---@param index integer
---@return table? stack
function Inventory:takeHalf(index)
    local current = self.slots[index]
    if not current then return nil end
    local half = math.ceil(current.count / 2)
    current.count = current.count - half
    if current.count == 0 then self.slots[index] = nil end
    return { id = current.id, count = half }
end

--- places one item from `stack` into an empty or matching slot
---@param index integer
---@param stack table
---@return table? remaining # nil once the stack is used up
function Inventory:putOne(index, stack)
    local current = self.slots[index]
    if current == nil then
        self.slots[index] = { id = stack.id, count = 1 }
    elseif current.id == stack.id and current.count < Items.get(stack.id).stack then
        current.count = current.count + 1
    else
        return stack
    end
    stack.count = stack.count - 1
    return stack.count > 0 and stack or nil
end

--- fills matching stacks first, then empty slots, within first..last (default:
-- every slot, hotbar first)
---@param id string
---@param count integer
---@param first? integer
---@param last? integer
---@return integer leftover
function Inventory:add(id, count, first, last)
    first, last = first or 1, last or self.size
    local max = Items.get(id).stack
    for i = first, last do
        local stack = self.slots[i]
        if stack and stack.id == id and stack.count < max then
            local moved = math.min(max - stack.count, count)
            stack.count = stack.count + moved
            count = count - moved
        end
    end
    for i = first, last do
        if count == 0 then break end
        if not self.slots[i] then
            local moved = math.min(max, count)
            self.slots[i] = { id = id, count = moved }
            count = count - moved
        end
    end
    return count
end

--- Tops `stack` up to its max from matching stacks in the slots, partial stacks
-- before full ones (Minecraft's double-click collect).
---@param stack table
function Inventory:gather(stack)
    local max = Items.get(stack.id).stack
    for pass = 1, 2 do
        for i = 1, self.size do
            local other = self.slots[i]
            if stack.count >= max then return end
            if other and other.id == stack.id and (other.count < max) == (pass == 1) then
                local moved = math.min(max - stack.count, other.count)
                stack.count = stack.count + moved
                other.count = other.count - moved
                if other.count == 0 then self.slots[i] = nil end
            end
        end
    end
end

--- a copy of every slot, for restore() to roll a multi-step change back
---@return table[] snapshot
function Inventory:snapshot()
    local copy = {}
    for i, stack in pairs(self.slots) do copy[i] = { id = stack.id, count = stack.count } end
    return copy
end

---@param snapshot table[]
function Inventory:restore(snapshot)
    self.slots = snapshot
end

--- exchanges two slots outright, even if both hold the same item - unlike
-- put(), this never merges, so a hotkeyed move never eats a slot's identity
---@param a integer
---@param b integer
function Inventory:swap(a, b)
    self.slots[a], self.slots[b] = self.slots[b], self.slots[a]
end

--- shift-click: sends a slot's stack to the other side (hotbar to storage,
-- storage to hotbar); whatever doesn't fit stays where it was
---@param index integer
function Inventory:quickMove(index)
    local stack = self.slots[index]
    if not stack then return end

    local first, last = 1, self.hotbarSize
    if index <= self.hotbarSize then first, last = self.hotbarSize + 1, self.size end

    local leftover = self:add(stack.id, stack.count, first, last)
    if leftover == 0 then self.slots[index] = nil else stack.count = leftover end
end

return Inventory
