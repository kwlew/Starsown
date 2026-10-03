--- The stats worker thread's lifecycle and its two channels.

local Worker = {}

local SCRIPT = "services/stats/thread.lua"

local thread, jobs, results
local generation = 0

--- abandons any current thread and starts a fresh one
---@param endpoint string
---@param clientId string
---@param cpath string|nil
---@return boolean ok
---@return string|nil err
function Worker.start(endpoint, clientId, cpath)
    if jobs then jobs:push("stop") end
    if not love.filesystem.getInfo(SCRIPT) then
        thread, jobs, results = nil, nil, nil
        return false, SCRIPT .. " is missing from this build"
    end

    generation = generation + 1
    local jobName, resultName = "stats.job." .. generation, "stats.result." .. generation
    jobs, results = love.thread.getChannel(jobName), love.thread.getChannel(resultName)
    thread = love.thread.newThread(SCRIPT)
    thread:start(endpoint, clientId, jobName, resultName, cpath)
    return true
end

---@return boolean
function Worker.isStarted()
    return thread ~= nil
end

---@param job table
function Worker.send(job)
    jobs:push(job)
end

---@return table|nil # the next reply, if any
function Worker.poll()
    return results and results:pop()
end

--- why the thread died, or nil while it's alive
---@return string|nil
function Worker.failure()
    if not thread then return nil end
    local err = thread:getError()
    if err then return err end
    if not thread:isRunning() then return "worker stopped without reporting an error" end
end

--- tells the thread to exit
function Worker.stop()
    if jobs then jobs:push("stop") end
    thread, jobs, results = nil, nil, nil
end

return Worker
