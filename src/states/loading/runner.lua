--- Runs weighted tasks as coroutines, a time budget per frame.
-- A failing task is recorded and skipped, never fatal.

local Math = require("utils.math")

local Runner = {}
Runner.__index = Runner

---@param tasks table[] # { label, weight?, run(yield, warn) }
---@return table
function Runner.new(tasks)
    local self = setmetatable({
        tasks = tasks,
        index = 1,
        doneWeight = 0,
        totalWeight = 0,
        partial = 0,
        coroutine = nil,
        failures = {},
    }, Runner)
    for _, task in ipairs(tasks) do self.totalWeight = self.totalWeight + (task.weight or 1) end
    self.yield = function(fraction) return coroutine.yield(fraction) end
    self.warn = function(detail) self:fail(detail) end
    return self
end

---@param detail any
function Runner:fail(detail)
    local task = self.tasks[self.index]
    self.failures[#self.failures + 1] = detail
    print(("[loading] task '%s' failed: %s"):format(task and task.label or "?", tostring(detail)))
end

---@return boolean
function Runner:isDone()
    return self.index > #self.tasks
end

---@return string|nil
function Runner:label()
    local task = self.tasks[self.index]
    return task and task.label
end

---@return number # 0..1, weighted, including the running task
function Runner:progress()
    if self.totalWeight == 0 then return 1 end
    local task = self.tasks[self.index]
    local partial = task and (task.weight or 1) * self.partial or 0
    return (self.doneWeight + partial) / self.totalWeight
end

--- resumes the current task once
function Runner:step()
    local task = self.tasks[self.index]
    if not task then return end
    if not self.coroutine then
        self.coroutine, self.partial = coroutine.create(task.run), 0
    end

    local ok, value = coroutine.resume(self.coroutine, self.yield, self.warn)
    if not ok then
        self:fail(value)
    elseif type(value) == "number" then
        self.partial = Math.clamp01(value)
    end

    if coroutine.status(self.coroutine) == "dead" then
        self.doneWeight = self.doneWeight + (task.weight or 1)
        self.index, self.coroutine, self.partial = self.index + 1, nil, 0
    end
end

--- steps until done or `budget` seconds pass
---@param budget number
function Runner:run(budget)
    local started = love.timer.getTime()
    repeat self:step() until self:isDone() or love.timer.getTime() - started >= budget
end

return Runner
