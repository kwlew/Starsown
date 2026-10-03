--- Turns variable frame time into whole fixed ticks.

local FixedStep = {}
FixedStep.__index = FixedStep

local MAX_TICKS_PER_FRAME = 5 -- drop the backlog after a hitch

---@param rate number # ticks per second
---@return table
function FixedStep.new(rate)
    return setmetatable({ tick = 1 / rate, accumulator = 0 }, FixedStep)
end

--- calls onTick for each tick the elapsed time covers
---@param dt number
---@param onTick fun(tick: number)
function FixedStep:advance(dt, onTick)
    self.accumulator = self.accumulator + dt
    local ticks = 0
    while self.accumulator >= self.tick and ticks < MAX_TICKS_PER_FRAME do
        onTick(self.tick)
        self.accumulator = self.accumulator - self.tick
        ticks = ticks + 1
    end
    if ticks == MAX_TICKS_PER_FRAME then self.accumulator = math.min(self.accumulator, self.tick) end
end

---@return number # 0..1 between the last tick and the next
function FixedStep:alpha()
    return self.accumulator / self.tick
end

return FixedStep
