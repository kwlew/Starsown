-- World-wide numbers: how many people are playing right now, and how many
-- shooting stars have been popped since the game existed. Owns the worker
-- thread, the anonymous client ID, and the opt-out. Screens just read:
--
--   if Stats.online then -- draw something with Stats.online end
--   if Stats.stars  then -- ...and with Stats.stars / Stats.golden end
--
-- and anything that pops a star calls Stats.pop(isGolden).
--
-- Every value stays nil until the first successful response, and a failed
-- request never clears one -- nil means "we don't know yet", and callers
-- should draw nothing rather than a 0 or an error.
--
-- One request carries everything: pops accumulate locally and ride out on the
-- same heartbeat that reports presence, so clicking stars costs no extra
-- traffic. See docs/shared-stats.md for the server side.
--
-- Succeeds the old onlineCount module. Unrelated to services/presence.lua (Discord).

local Json = require "vendor.json"

local Stats = {}

local ENDPOINT = "https://tdidle-presence.kwlew.workers.dev/stats"
-- seconds between heartbeats; requests/day per player = 86400/INTERVAL, and
-- the server's window must stay >= 2x this or one dropped request flickers a player out
local INTERVAL = 60
local ID_FILE = "client_id"
local PENDING_FILE = "stats_pending"
local WORKER = "services/threads/stats.lua" -- love.filesystem-relative (root is src/)

-- stars/request the server accepts before rejecting outright; keep in step with MAX_REPORT in the worker
local MAX_REPORT = 400

-- backlog ceiling; past this it's either a very long offline session or not a
-- player, and there's no point growing a number the server will spend hours draining
local MAX_PENDING = 5000

Stats.online = nil
Stats.stars = nil
Stats.golden = nil
Stats.enabled = true

local thread, jobChannel, resultChannel
local timer = INTERVAL -- fire the first heartbeat immediately
local loadedPending = false

-- pops waiting to send vs. currently on the wire, split so a failed request
-- can put back exactly what it took without swallowing pops made mid-flight
local pending = { stars = 0, golden = 0 }
local inflight = nil

-- bumped every start so each thread gets its own channel pair -- a shared
-- channel let a still-finishing old thread swallow the new thread's stop
-- token, or push a stale count into the new one
local generation = 0

-- random v4 UUID, not derived from hardware/username: exists only so the
-- server can tell two running copies apart
local function uuid()
    -- love.math's default seed isn't guaranteed to differ between installs
    love.math.setRandomSeed(os.time() + math.floor(os.clock() * 1000000))
    return (("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"):gsub("[xy]", function(c)
        local v = (c == "x") and love.math.random(0, 15) or love.math.random(8, 11)
        return string.format("%x", v)
    end))
end

-- stable per-install ID, generated once, kept next to settings.lua.
-- >= not >: a UUID is exactly 36 chars, so a > test would reject every ID we
-- ever wrote and mint a fresh one on every launch
local function clientId()
    local saved = love.filesystem.read(ID_FILE)
    if saved and #saved >= 36 then return saved:sub(1, 36) end
    local id = uuid()
    love.filesystem.write(ID_FILE, id)
    return id
end

-- pops that never made it out before the game closed; without this, quitting
-- inside the heartbeat window (most sessions) would drop that session's pops.
-- Read once and deleted immediately -- the backlog is authoritative in memory
-- from here on, so a stale file can't get double-counted after a crash.
local function loadPending()
    loadedPending = true -- guards savePending: a session that never read the file must not rewrite/delete it

    local saved = love.filesystem.read(PENDING_FILE)
    if not saved then return end
    love.filesystem.remove(PENDING_FILE)

    local stars, golden = saved:match("^(%d+)%s+(%d+)")
    stars, golden = tonumber(stars), tonumber(golden)
    if not stars or not golden or golden > stars then return end -- hand-edited/truncated file: don't trust it

    pending.stars = math.min(stars, MAX_PENDING)
    pending.golden = math.min(golden, pending.stars)
end

local function savePending()
    if not loadedPending then return end
    if pending.stars <= 0 then
        love.filesystem.remove(PENDING_FILE)
        return
    end
    love.filesystem.write(PENDING_FILE, ("%d %d"):format(pending.stars, pending.golden))
end

local function newWorkerThread()
    if not love.filesystem.getInfo(WORKER) then return nil end
    return love.thread.newThread(WORKER)
end

-- moves a chunk of the backlog onto the wire; chunked because the server caps
-- a single report and refuses an over-cap one outright rather than clamping
local function dispatch()
    local stars = math.min(pending.stars, MAX_REPORT)
    local golden = math.min(pending.golden, stars)

    pending.stars = pending.stars - stars
    pending.golden = pending.golden - golden
    inflight = { stars = stars, golden = golden }

    -- hand-rolled, not Json.encode: two integers, and it keeps the worker free of our modules
    jobChannel:push{
        body = ('{"stars":%d,"golden":%d}'):format(stars, golden),
        stars = stars,
        golden = golden,
    }
end

local function requeue(stars, golden)
    pending.stars = math.min(pending.stars + stars, MAX_PENDING)
    pending.golden = math.min(pending.golden + golden, pending.stars)
end

-- a 4xx other than 429 means the server rejected this payload and would
-- reject an identical retry forever; anything else (no code, 5xx, 429) is a "later"
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
            end
        elseif retryable(result.code) then
            requeue(result.stars, result.golden)
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

-- cheap enough to call straight from a click handler: moves two integers, never touches the network
function Stats.pop(golden)
    if not Stats.enabled then return end
    if pending.stars >= MAX_PENDING then return end

    pending.stars = pending.stars + 1
    if golden then pending.golden = pending.golden + 1 end
end

function Stats.shutdown()
    readResults() -- read whatever came back first, or a just-succeeded report gets counted again next launch
    if inflight then
        requeue(inflight.stars, inflight.golden)
        inflight = nil
    end
    savePending() -- before the early return: no https module means no thread, but the backlog still needs saving

    if not thread then return end

    jobChannel:push("stop") -- the thread is blocked in demand(), so this wakes it within a frame
    thread, jobChannel, resultChannel = nil, nil, nil
end

-- live opt-in/opt-out for the Options toggle; must stop the heartbeat
-- immediately and drop every value so the menu stops showing frozen figures
function Stats.setEnabled(enabled)
    if enabled == Stats.enabled then return end
    Stats.enabled = enabled

    if enabled then
        Stats.start()
        return
    end

    Stats.shutdown()
    Stats.online, Stats.stars, Stats.golden = nil, nil, nil
    -- opting out means opting out of the backlog too, not sending it the moment they opt back in
    pending.stars, pending.golden = 0, 0
    love.filesystem.remove(PENDING_FILE)
end

return Stats
