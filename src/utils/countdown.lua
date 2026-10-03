--- A one-shot timer: counts down, fires once, then clears itself.
--
--   local timer = Countdown.new(10, function() revert() end)
--   timer:update(dt)
--   timer:remaining()   -- nil once fired or stopped

local Countdown = {}
Countdown.__index = Countdown

---@param duration? number # seconds; nil makes a countdown that never runs
---@param onDone? fun()
---@return table
function Countdown.new(duration, onDone)
    return setmetatable({ duration = duration, onDone = onDone, left = nil }, Countdown)
end

--- (re)starts from the full duration
function Countdown:start()
    self.left = self.duration
end

function Countdown:stop()
    self.left = nil
end

---@return number|nil # seconds left, or nil when not running
function Countdown:remaining()
    return self.left
end

---@param dt number
function Countdown:update(dt)
    if not self.left then return end
    self.left = self.left - dt
    if self.left <= 0 then
        self.left = nil
        if self.onDone then self.onDone() end
    end
end

return Countdown
