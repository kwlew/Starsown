--- A stamina bar: drains while sprinting, refills after a pause.
-- An emptied bar must partly refill before sprinting again.

local Stamina = {}
Stamina.__index = Stamina

local DRAIN = 30 -- per second sprinting
local REGEN = 25 -- per second resting
local REGEN_DELAY = 0.8
local RECOVER_AT = 0.3 -- of max, after exhaustion

---@param max number
---@return table
function Stamina.new(max)
    return setmetatable({ max = max, value = max, exhausted = false, delay = 0 }, Stamina)
end

---@return boolean
function Stamina:canSprint()
    return not self.exhausted
end

---@param dt number
---@param sprinting boolean
function Stamina:update(dt, sprinting)
    if sprinting then
        self.value = math.max(0, self.value - DRAIN * dt)
        self.delay = REGEN_DELAY
        if self.value == 0 then self.exhausted = true end
        return
    end
    self.delay = math.max(0, self.delay - dt)
    if self.delay == 0 then self.value = math.min(self.max, self.value + REGEN * dt) end
    if self.exhausted and self.value >= self.max * RECOVER_AT then self.exhausted = false end
end

return Stamina
