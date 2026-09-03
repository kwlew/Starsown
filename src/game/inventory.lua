--- A fixed run of slots. A slot is nil or { id = "scrap", count = n }; nothing
-- outside here should build one by hand, since take/put hand them back and
-- forth already.
--
--   local bag = Inventory.new{ slots = 24 }
--   local leftover = bag:add("scrap", 10)   -- 0 when it all fit
--   bag:move(1, 5)                          -- merge onto slot 5, or swap
--
-- take/put are the pair the panel drags with: take() lifts a stack out, put()
-- drops one in and returns whatever it displaced, so the caller is always
-- holding at most one stack and nothing can be duplicated or lost.

local Items = require "game.items"

local Inventory = {}
Inventory.__index = Inventory

local DEFAULT_SLOTS = 24

---@param config? table # { slots?: integer }
---@return table
function Inventory.new(config)
    config = config or {}
    return setmetatable({
        size = config.slots or DEFAULT_SLOTS,
        slots = {},
    }, Inventory)
end

---@param index integer
---@return table|nil # { id: string, count: integer }; the live slot, not a copy
function Inventory:get(index)
    return self.slots[index]
end

---@return boolean
function Inventory:isEmpty()
    for i = 1, self.size do
        if self.slots[i] then return false end
    end
    return true
end

--- across every slot, not just the first
---@param id string
---@return integer
function Inventory:count(id)
    local total = 0
    for i = 1, self.size do
        local slot = self.slots[i]
        if slot and slot.id == id then total = total + slot.count end
    end
    return total
end

--- tops up partial stacks before opening a fresh slot, so picking things up
-- doesn't fragment the bag. Returns what wouldn't fit.
---@param id string # an unknown item is refused outright
---@param count? integer # defaults to 1
---@return integer # leftover; 0 when it all fit
function Inventory:add(id, count)
    count = count or 1
    if count <= 0 or not Items.get(id) then return count end
    local stack = Items.stack(id)

    for i = 1, self.size do
        local slot = self.slots[i]
        if slot and slot.id == id and slot.count < stack then
            local moved = math.min(stack - slot.count, count)
            slot.count = slot.count + moved
            count = count - moved
            if count == 0 then return 0 end
        end
    end

    for i = 1, self.size do
        if not self.slots[i] then
            local moved = math.min(stack, count)
            self.slots[i] = { id = id, count = moved }
            count = count - moved
            if count == 0 then return 0 end
        end
    end

    return count
end

--- lifts the whole stack out, leaving the slot empty
---@param index integer
---@return table|nil # { id: string, count: integer }
function Inventory:take(index)
    local slot = self.slots[index]
    self.slots[index] = nil
    return slot
end

--- half rounded up, so taking half of one leaves nothing behind rather than
-- splitting a stack that can't be split
---@param index integer
---@return table|nil # { id: string, count: integer }
function Inventory:takeHalf(index)
    local slot = self.slots[index]
    if not slot then return nil end

    local half = math.ceil(slot.count / 2)
    slot.count = slot.count - half
    if slot.count == 0 then self.slots[index] = nil end
    return { id = slot.id, count = half }
end

--- merges onto a matching stack, swaps otherwise; returns the leftover (nil
-- when the whole stack fit)
---@param index integer
---@param stack table|nil # { id: string, count: integer }
---@return table|nil # { id: string, count: integer }; leftover, or what was displaced
function Inventory:put(index, stack)
    if not stack then return nil end

    local slot = self.slots[index]
    if not slot then
        self.slots[index] = { id = stack.id, count = stack.count }
        return nil
    end

    if slot.id == stack.id then
        local moved = math.min(Items.stack(slot.id) - slot.count, stack.count)
        slot.count = slot.count + moved
        stack.count = stack.count - moved
        if stack.count == 0 then return nil end
        return stack
    end

    self.slots[index] = { id = stack.id, count = stack.count }
    return slot
end

--- one of `stack` into a slot; the leftover is what the caller keeps holding
---@param index integer
---@param stack table|nil # { id: string, count: integer }
---@return table|nil # { id: string, count: integer }
function Inventory:putOne(index, stack)
    if not stack then return nil end

    local slot = self.slots[index]
    if slot and (slot.id ~= stack.id or slot.count >= Items.stack(slot.id)) then
        return stack
    end

    self:put(index, { id = stack.id, count = 1 })
    stack.count = stack.count - 1
    if stack.count == 0 then return nil end
    return stack
end

--- merge or swap between two slots
---@param from integer
---@param to integer
function Inventory:move(from, to)
    if from == to then return end
    self.slots[from] = self:put(to, self:take(from))
end

return Inventory
