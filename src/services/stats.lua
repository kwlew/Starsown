-- src/services/stats.lua
local Json = require "vendor.json"

local Stats = {}

local ENDPOINT = "https://tdidle-presence.kwlew.workers.dev/stats"

local INTERVAL = 60
local ID_FILE = "client_id"
local PENDING_FILE = "stats_pending"
local WORKER = "services/threads/stats.lua" -- love.filesystem-relative (root is src/)

local MAX_REPORT = 400

local MAX_PENDING = 5000

Stats.online = nil
Stats.stars = nil
Stats.golden = nil
Stats.rainbow = nil
Stats.enabled = true

local thread, jobChannel, resultChannel
local timer = INTERVAL
local loadedPending = false

local pending = { stars = 0, golden = 0, rainbow = 0 }
local inflight = nil

local generation = 0

-- Folds an arbitrary string into a non-negative number; used below to mix a
-- fresh table's own memory address into the seed without caring what
-- format tostring() happens to print it in on a given platform/Lua build.
local function hashString(s)
    local h = 0
    for i = 1, #s do
        h = (h * 31 + s:byte(i)) % 2^31
    end
    return h
end

-- os.time() alone is a second-resolution value anyone who knows roughly
-- when the game launched can narrow to a handful of guesses, and
-- os.clock() this early in boot is bounded to whatever sliver of CPU time
-- the process has used so far -- neither carries remotely enough entropy
-- for something meant to tell two installs apart, and using just those two
-- means two players who happen to launch around the same moment (hardly a
-- rare case) have an elevated chance of colliding IDs. tostring() on a
-- table exposes its heap address, which moves with allocation history and
-- ASLR and isn't derivable from outside the process -- mixing that in is
-- what actually defeats "I know when you launched, so I can guess your ID."
local function uuidSeed()
    return (os.time() * 1000003 + math.floor(os.clock() * 1000000) + hashString(tostring({}))) % 2^31
end

-- random v4 UUID.
local function uuid()
    love.math.setRandomSeed(uuidSeed())
    return (("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"):gsub("[xy]", function(c)
        local v = (c == "x") and love.math.random(0, 15) or love.math.random(8, 11)
        return string.format("%x", v)
    end))
end

local function clientId()
    local saved = love.filesystem.read(ID_FILE)
    if saved and #saved >= 36 then return saved:sub(1, 36) end
    local id = uuid()
    love.filesystem.write(ID_FILE, id)
    return id
end

local function loadPending()
    loadedPending = true -- guards savePending: a session that never read the file must not rewrite/delete it

    local saved = love.filesystem.read(PENDING_FILE)
    if not saved then return end
    love.filesystem.remove(PENDING_FILE)

    local stars, golden, rainbow = saved:match("^(%d+)%s+(%d+)%s+(%d+)")
    if not stars then -- written before rainbow stars existed: two fields, no rainbow
        stars, golden = saved:match("^(%d+)%s+(%d+)")
        rainbow = "0"
    end
    stars, golden, rainbow = tonumber(stars), tonumber(golden), tonumber(rainbow)

    if not stars or not golden or golden + rainbow > stars then return end

    pending.stars = math.min(stars, MAX_PENDING)
    pending.golden = math.min(golden, pending.stars)
    pending.rainbow = math.min(rainbow, pending.stars - pending.golden)
end

local function savePending()
    if not loadedPending then return end
    if pending.stars <= 0 then
        love.filesystem.remove(PENDING_FILE)
        return
    end
    love.filesystem.write(PENDING_FILE, ("%d %d %d"):format(pending.stars, pending.golden, pending.rainbow))
end

local function newWorkerThread()
    if not love.filesystem.getInfo(WORKER) then return nil end
    return love.thread.newThread(WORKER)
end

local function dispatch()
    local stars = math.min(pending.stars, MAX_REPORT)
    local golden = math.min(pending.golden, stars)
    local rainbow = math.min(pending.rainbow, stars - golden)

    pending.stars = pending.stars - stars
    pending.golden = pending.golden - golden
    pending.rainbow = pending.rainbow - rainbow
    inflight = { stars = stars, golden = golden, rainbow = rainbow }

    jobChannel:push{
        body = ('{"stars":%d,"golden":%d,"rainbow":%d}'):format(stars, golden, rainbow),
        stars = stars,
        golden = golden,
        rainbow = rainbow,
    }
end

local function requeue(stars, golden, rainbow)
    pending.stars = math.min(pending.stars + stars, MAX_PENDING)
    pending.golden = math.min(pending.golden + golden, pending.stars)
    pending.rainbow = math.min(pending.rainbow + rainbow, pending.stars - pending.golden)
end

local function retryable(code)
    if not code then return true end
    return code < 400 or code >= 500 or code == 429
end

local function readResults()
    if not resultChannel then return end

    local result = resultChannel:pop() -- drain, not pop-once: a stalled frame can queue more than one response
    while result do
        inflight = nil -- answered either way; whether it goes back into the backlog is separate

        if result.code == 200 then
            local ok, data = pcall(Json.decode, result.body or "")
            if ok and type(data) == "table" then
                if type(data.online) == "number" then Stats.online = math.floor(data.online) end
                if type(data.stars) == "number" then Stats.stars = math.floor(data.stars) end
                if type(data.golden) == "number" then Stats.golden = math.floor(data.golden) end
                if type(data.rainbow) == "number" then Stats.rainbow = math.floor(data.rainbow) end
            end
        elseif retryable(result.code) then
            requeue(result.stars, result.golden, result.rainbow)
        end

        result = resultChannel:pop()
    end
end

function Stats.start()
    if thread or not Stats.enabled then return end

    loadPending()

    generation = generation + 1
    local jobName    = "stats.job." .. generation
    local resultName = "stats.result." .. generation

    thread = newWorkerThread()
    if not thread then return end -- nothing to fall back to; the menu just never shows a figure

    jobChannel    = love.thread.getChannel(jobName)
    resultChannel = love.thread.getChannel(resultName)
    timer = INTERVAL
    inflight = nil

    thread:start(ENDPOINT, clientId(), jobName, resultName)
end

function Stats.update(dt)
    if not thread then return end

    readResults()

    timer = timer + (dt or 0)
    if timer < INTERVAL then return end
    if inflight then return end -- one request at a time, or a landed first request gets double-reported

    timer = 0
    dispatch()
end

function Stats.pop(kind)
    if not Stats.enabled then return end
    if pending.stars >= MAX_PENDING then return end

    pending.stars = pending.stars + 1
    if kind == "golden" then
        pending.golden = pending.golden + 1
    elseif kind == "rainbow" then
        pending.rainbow = pending.rainbow + 1
    end
end

function Stats.shutdown()
    readResults() -- read whatever came back first, or a just-succeeded report gets counted again next launch
    if inflight then
        requeue(inflight.stars, inflight.golden, inflight.rainbow)
        inflight = nil
    end
    savePending() -- before the early return: no https module means no thread, but the backlog still needs saving

    if not thread then return end

    jobChannel:push("stop") -- the thread is blocked in demand(), so this wakes it within a frame
    thread, jobChannel, resultChannel = nil, nil, nil
end

function Stats.setEnabled(enabled)
    if enabled == Stats.enabled then return end
    Stats.enabled = enabled

    if enabled then
        Stats.start()
        return
    end

    Stats.shutdown()
    Stats.online, Stats.stars, Stats.golden, Stats.rainbow = nil, nil, nil, nil
    pending.stars, pending.golden, pending.rainbow = 0, 0, 0
    love.filesystem.remove(PENDING_FILE)
end

return Stats
