local Json = require "vendor.json"
local Settings = require "core.settings"

local Stats = {}

local ENDPOINT = "https://tdidle-presence.kwlew.workers.dev/stats"

local INTERVAL = 5
local ID_FILE = "client_id"
local PENDING_FILE = "stats_pending"
local WORKER = "services/threads/stats.lua" -- love.filesystem-relative (root is src/)

local MAX_REPORT = 400

local MAX_PENDING = 5000

-- how long an `inflight` request may sit unanswered before the watchdog
-- below gives up on it and abandons the worker -- lua-https has no working
-- request-timeout option of its own, so this is the only place a genuinely
-- stalled (not just slow-to-error) connection ever gets noticed
local STATS_TIMEOUT = 10
local EXTENDED_INTERVAL_CAP = 180 -- backoff ceiling for a host that stays unresponsive

Stats.online = nil
Stats.stars = nil
Stats.golden = nil
Stats.rainbow = nil
Stats.enabled = true

Stats.startedAt = nil -- love.timer.getTime() of the last Stats.start(); nil until one is attempted --
-- lets a screen tell "just asked, still waiting on the first reply" from "been trying a while"
Stats.lastUpdated = nil -- love.timer.getTime() of the last successful reply; nil until one arrives

local thread, jobChannel, resultChannel
local timer = INTERVAL
local loadedPending = false

local pending = { stars = 0, golden = 0, rainbow = 0 }
local inflight = nil
local inflightSince = nil -- love.timer.getTime() `inflight` was set; nil whenever inflight is
local consecutiveTimeouts = 0 -- watchdog hits in a row since the last real reply; drives the backoff below

local generation = 0

--- Folds an arbitrary string into a non-negative number; used below to mix a
-- fresh table's own memory address into the seed without caring what
-- format tostring() happens to print it in on a given platform/Lua build.
---@param s string
---@return number
local function hashString(s)
    local h = 0
    for i = 1, #s do
        h = (h * 31 + s:byte(i)) % 2^31
    end
    return h
end

--- os.time() alone is a second-resolution value anyone who knows roughly
-- when the game launched can narrow to a handful of guesses, and
-- os.clock() this early in boot is bounded to whatever sliver of CPU time
-- the process has used so far -- neither carries remotely enough entropy
-- for something meant to tell two installs apart, and using just those two
-- means two players who happen to launch around the same moment (hardly a
-- rare case) have an elevated chance of colliding IDs. tostring() on a
-- table exposes its heap address, which moves with allocation history and
-- ASLR and isn't derivable from outside the process -- mixing that in is
-- what actually defeats "I know when you launched, so I can guess your ID."
---@return number
local function uuidSeed()
    return (os.time() * 1000003 + math.floor(os.clock() * 1000000) + hashString(tostring({}))) % 2^31
end

--- random v4 UUID
---@return string
local function uuid()
    love.math.setRandomSeed(uuidSeed())
    return (("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"):gsub("[xy]", function(c)
        local v = (c == "x") and love.math.random(0, 15) or love.math.random(8, 11)
        return string.format("%x", v)
    end))
end

--- this install's id, generated and saved on first use. Only ever a random
-- UUID -- nothing about the machine or the player goes into it.
---@return string
local function clientId()
    local saved = love.filesystem.read(ID_FILE)
    if saved and #saved >= 36 then return saved:sub(1, 36) end
    local id = uuid()
    love.filesystem.write(ID_FILE, id)
    return id
end

--- reads back the pop counts a previous session couldn't deliver, then removes
-- the file so a crash mid-send can't double-report them. Values are sanity
-- checked and clamped, and a file that doesn't add up is dropped entirely.
-- Also handles the older two-field format, written before rainbow stars.
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

    if not stars or not golden or not rainbow or golden + rainbow > stars then return end

    pending.stars = math.min(stars, MAX_PENDING)
    pending.golden = math.min(golden, pending.stars)
    pending.rainbow = math.min(rainbow, pending.stars - pending.golden)
end

--- writes the undelivered backlog for the next launch
local function savePending()
    if not loadedPending then return end
    if pending.stars <= 0 then
        love.filesystem.remove(PENDING_FILE)
        return
    end
    love.filesystem.write(PENDING_FILE, ("%d %d %d"):format(pending.stars, pending.golden, pending.rainbow))
end

---@return any # a love.Thread, or nil when the worker file isn't there
local function newWorkerThread()
    if not love.filesystem.getInfo(WORKER) then return nil end
    return love.thread.newThread(WORKER)
end

--- abandons whatever worker is currently wired up -- a hung one can't be
-- cancelled, only dropped, since LÖVE has no thread-kill primitive -- and
-- wires up a fresh one under a new channel generation. The generation bump
-- matters even though the old worker is discarded either way: it's blocked
-- inside https.request, not waiting at demand(), so if it ever does unblock
-- its late reply must land on a channel nothing reads anymore rather than
-- being mistaken for a reply to whatever request comes next.
local function spinUpWorker()
    generation = generation + 1
    local jobName    = "stats.job." .. generation
    local resultName = "stats.result." .. generation

    thread = newWorkerThread()
    if not thread then return end -- nothing to fall back to; the menu just never shows a figure

    jobChannel    = love.thread.getChannel(jobName)
    resultChannel = love.thread.getChannel(resultName)
    thread:start(ENDPOINT, clientId(), jobName, resultName)
end

--- sends up to MAX_REPORT pops, moving them out of the backlog and into
-- `inflight` -- so a failed request can put exactly those back
local function dispatch()
    local stars = math.min(pending.stars, MAX_REPORT)
    local golden = math.min(pending.golden, stars)
    local rainbow = math.min(pending.rainbow, stars - golden)

    pending.stars = pending.stars - stars
    pending.golden = pending.golden - golden
    pending.rainbow = pending.rainbow - rainbow
    inflight = { stars = stars, golden = golden, rainbow = rainbow }
    inflightSince = love.timer.getTime()

    jobChannel:push{
        body = ('{"stars":%d,"golden":%d,"rainbow":%d}'):format(stars, golden, rainbow),
        stars = stars,
        golden = golden,
        rainbow = rainbow,
    }
end

--- puts an undelivered report back into the backlog, capped so an endpoint
-- that's been down for a long time can't grow it without bound. Takes the
-- same {stars, golden, rainbow} shape `inflight` and a worker result both
-- already carry, so callers never unpack just to repack.
---@param counts { stars: integer, golden: integer, rainbow: integer }
local function requeue(counts)
    pending.stars = math.min(pending.stars + counts.stars, MAX_PENDING)
    pending.golden = math.min(pending.golden + counts.golden, pending.stars)
    pending.rainbow = math.min(pending.rainbow + counts.rainbow, pending.stars - pending.golden)
end

--- clears the inflight bookkeeping -- the two fields always move together,
-- so this is the one place that has to remember that
local function clearInflight()
    inflight, inflightSince = nil, nil
end

---@param code integer|nil # nil means the request never completed
---@return boolean # false only for a 4xx the server won't answer differently next time
local function retryable(code)
    if not code then return true end
    return code < 400 or code >= 500 or code == 429
end

--- drains the worker's replies. A failed request never clears a value -- nil
-- means "unknown" and screens draw nothing rather than a 0.
local function readResults()
    if not resultChannel then return end

    local result = resultChannel:pop() -- drain, not pop-once: a stalled frame can queue more than one response
    while result do
        clearInflight() -- answered either way; whether it goes back into the backlog is separate
        consecutiveTimeouts = 0 -- a reply of any kind proves the worker+network path still works

        if result.code == 200 then
            local ok, data = pcall(Json.decode, result.body or "")
            if ok and type(data) == "table" then
                Stats.lastUpdated = love.timer.getTime()
                if type(data.online) == "number" then Stats.online = math.floor(data.online) end
                if type(data.stars) == "number" then Stats.stars = math.floor(data.stars) end
                if type(data.golden) == "number" then Stats.golden = math.floor(data.golden) end
                if type(data.rainbow) == "number" then Stats.rainbow = math.floor(data.rainbow) end
            end
        elseif retryable(result.code) then
            requeue(result)
        end

        result = resultChannel:pop()
    end
end

--- an `inflight` request that's sat unanswered past STATS_TIMEOUT is treated
-- as failed: its counts go back into the backlog and the stuck worker --
-- blocked inside https.request, not listening on a channel -- is abandoned
-- in favor of a fresh one, so a stalled connection doesn't wedge reporting
-- for the rest of the session.
local function checkWatchdog()
    if not inflight or not inflightSince then return end
    if love.timer.getTime() - inflightSince < STATS_TIMEOUT then return end

    requeue(inflight)
    clearInflight()
    consecutiveTimeouts = consecutiveTimeouts + 1

    if jobChannel then jobChannel:push("stop") end -- in case the stuck worker ever does unblock
    spinUpWorker()
end

--- backs off the retry cadence after repeated timeouts, so a host that stays
-- unresponsive doesn't spin up (and orphan) a fresh worker thread every
-- INTERVAL for the rest of a long session
---@return number
local function effectiveInterval()
    return math.min(INTERVAL * 2 ^ consecutiveTimeouts, EXTENDED_INTERVAL_CAP)
end

--- starts the reporting thread, replaying any backlog from last session. A
-- missing lua-https (the LÖVE Windows installer doesn't bundle it) degrades to
-- no stats rather than a crash.
function Stats.start()
    if thread or not Stats.enabled then return end

    Stats.startedAt = love.timer.getTime()
    loadPending()

    timer = INTERVAL
    clearInflight()
    consecutiveTimeouts = 0

    spinUpWorker()
end

--- reads replies every frame, and sends at most one request per interval
---@param dt number
function Stats.update(dt)
    if not thread then return end

    readResults()
    checkWatchdog()

    timer = timer + (dt or 0)
    if timer < effectiveInterval() then return end
    if inflight then return end -- one request at a time, or a landed first request gets double-reported

    timer = 0
    dispatch()
end

--- counts one popped star toward the next report
---@param kind? "golden"|"rainbow" # plain stars pass nothing
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

--- call on quit: drains what came back, puts anything unanswered back into the
-- backlog, saves it, and stops the thread
function Stats.shutdown()
    readResults() -- read whatever came back first, or a just-succeeded report gets counted again next launch
    if inflight then
        requeue(inflight)
        clearInflight()
    end
    savePending() -- before the early return: no https module means no thread, but the backlog still needs saving

    if not thread then return end

    jobChannel:push("stop") -- the thread is blocked in demand(), so this wakes it within a frame
    thread, jobChannel, resultChannel = nil, nil, nil
end

--- forgets the counters, the backlog and the client id -- everything this
-- machine holds about stats sharing
local function clearLocalData()
    Stats.online, Stats.stars, Stats.golden, Stats.rainbow = nil, nil, nil, nil
    Stats.startedAt, Stats.lastUpdated = nil, nil
    pending.stars, pending.golden, pending.rainbow = 0, 0, 0
    love.filesystem.remove(PENDING_FILE)
    love.filesystem.remove(ID_FILE)
end

--- turning sharing off stops the thread and clears local data; a redundant
-- "off" still clears, so the opt-out is idempotent
---@param enabled boolean
function Stats.setEnabled(enabled)
    if enabled == Stats.enabled then
        if not enabled then clearLocalData() end
        return
    end
    Stats.enabled = enabled

    if enabled then
        Stats.start()
        return
    end

    Stats.shutdown()
    clearLocalData()
end

--- records the player's consent (accept or decline), persists it, and
-- applies it -- the one place "the player answered the consent question"
-- happens, so the first-run dialog and any later re-ask (e.g. the Stats
-- screen's own enable-sharing shortcut) can't drift out of step with each
-- other on what answering actually does
---@param settings table
---@param enabled boolean
function Stats.setConsent(settings, enabled)
    settings.shareStats = enabled
    settings.statsConsentAsked = true
    Settings.save(settings)
    Stats.setEnabled(enabled)
end

return Stats
