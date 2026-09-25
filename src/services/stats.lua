local Json = require "vendor.json"
local Settings = require "core.settings"
local Diagnostics = require "core.diagnostics"

local Stats = {}

local NAME = "stats" -- this service's name in Diagnostics
local ENDPOINT = "https://tdidle-presence.kwlew.workers.dev/stats"
local endpoint = ENDPOINT

local INTERVAL = 5
local ID_FILE = "client_id"
local PENDING_FILE = "stats_pending"
local WORKER = "services/threads/stats.lua" -- love.filesystem-relative (root is src/)

local MAX_REPORT = 400

local MAX_PENDING = 5000

local STATS_TIMEOUT = 10
local EXTENDED_INTERVAL_CAP = 180 -- backoff ceiling for a host that stays unresponsive

Stats.online = nil
Stats.stars = nil
Stats.golden = nil
Stats.rainbow = nil
Stats.enabled = true

Stats.startedAt = nil
Stats.lastUpdated = nil

local thread, jobChannel, resultChannel
local timer = INTERVAL
local loadedPending = false

local pending = { stars = 0, golden = 0, rainbow = 0 }
local inflight = nil
local inflightSince = nil
local consecutiveTimeouts = 0
local fatal = false -- a failure retrying can't fix (no https, no worker); reporting stops until restarted

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

--- Make a random seed that changes every time the game is launched, but is stable.
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

--- reads back the pop counts a previous session couldn't deliver.
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

--- stops reporting for this session with a reason the player can quote;
-- the backlog stays and is saved as usual
---@param code string
---@param detail any
local function fail(code, detail)
    fatal = true
    Diagnostics.report(NAME, code, detail)
    Diagnostics.setStatus(NAME, "error")
end

--- LÖVE won't load C modules from the game folder, so an unpackaged
-- `love src` run points the worker at the dev build of lua-https that
-- tools/ keeps in .tools/lua-https, when it's there
---@return string|nil # a package.cpath entry
local function devCpath()
    if love.filesystem.isFused() then return nil end
    local source = love.filesystem.getSource()
    local ext = love.system.getOS() == "Windows" and "dll" or "so"
    local path = source .. "/../.tools/lua-https/https." .. ext
    local file = io.open(path, "rb")
    if not file then return nil end
    file:close()
    return source .. "/../.tools/lua-https/?." .. ext
end

--- Abandons the current worker and starts a new one, with a fresh channel pair.
local function spinUpWorker()
    generation = generation + 1
    local jobName    = "stats.job." .. generation
    local resultName = "stats.result." .. generation

    if not love.filesystem.getInfo(WORKER) then
        thread = nil
        return fail("ST-NOWORKER", WORKER .. " is missing from this build")
    end
    thread = love.thread.newThread(WORKER)

    jobChannel    = love.thread.getChannel(jobName)
    resultChannel = love.thread.getChannel(resultName)
    thread:start(endpoint, clientId(), jobName, resultName, devCpath())
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
-- that's been down for a long time can't grow it without bound.
---@param counts { stars: integer, golden: integer, rainbow: integer }
local function requeue(counts)
    pending.stars = math.min(pending.stars + counts.stars, MAX_PENDING)
    pending.golden = math.min(pending.golden + counts.golden, pending.stars)
    pending.rainbow = math.min(pending.rainbow + counts.rainbow, pending.stars - pending.golden)
end

--- Clears the inflight bookkeeping.
local function clearInflight()
    inflight, inflightSince = nil, nil
end

---@param code integer|nil # nil means the request never completed
---@return boolean # false only for a 4xx the server won't answer differently next time
local function retryable(code)
    if not code then return true end
    return code < 400 or code >= 500 or code == 429
end

---@param body any
---@return string # the start of a response body, enough to recognise an error page
local function snippet(body)
    if type(body) ~= "string" or body == "" then return "empty body" end
    return body:sub(1, 160)
end

--- one reply from the worker
---@param result table
local function handleResult(result)
    if result.fatal then return fail(result.fatal, result.detail) end

    clearInflight() -- answered either way; whether it goes back into the backlog is separate
    consecutiveTimeouts = 0 -- a reply of any kind proves the worker+network path still works

    if result.failure then
        requeue(result)
        Diagnostics.report(NAME, "ST-NET", result.failure)
        Diagnostics.setStatus(NAME, "error")
        return
    end

    if result.code ~= 200 then
        if retryable(result.code) then requeue(result) end
        Diagnostics.report(NAME, "ST-HTTP-" .. tostring(result.code), snippet(result.body))
        Diagnostics.setStatus(NAME, "error")
        return
    end

    local ok, data = pcall(Json.decode, result.body or "")
    if not ok or type(data) ~= "table" then
        Diagnostics.report(NAME, "ST-BADREPLY", snippet(result.body))
        Diagnostics.setStatus(NAME, "error")
        return
    end
    Stats.lastUpdated = love.timer.getTime()
    if type(data.online) == "number" then Stats.online = math.floor(data.online) end
    if type(data.stars) == "number" then Stats.stars = math.floor(data.stars) end
    if type(data.golden) == "number" then Stats.golden = math.floor(data.golden) end
    if type(data.rainbow) == "number" then Stats.rainbow = math.floor(data.rainbow) end
    Diagnostics.clear(NAME)
    Diagnostics.setStatus(NAME, "ok")
end

--- drains the worker's replies. A failed request never clears a value -- nil
-- means "unknown" and screens draw nothing rather than a 0.
local function readResults()
    if not resultChannel then return end

    local result = resultChannel:pop() -- drain, not pop-once: a stalled frame can queue more than one response
    while result do
        handleResult(result)
        if fatal then return end
        result = resultChannel:pop()
    end
end

--- a worker that errored, or stopped without saying why, would otherwise
-- leave requests unanswered until the watchdog, forever
local function checkWorker()
    local err = thread:getError()
    if err then return fail("ST-CRASH", err) end
    if thread:isRunning() then return end
    readResults() -- it may have pushed its reason just before exiting
    if not fatal then fail("ST-CRASH", "worker stopped without reporting an error") end
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
    Diagnostics.report(NAME, "ST-TIMEOUT", ("no reply from %s within %ds"):format(endpoint, STATS_TIMEOUT))
    Diagnostics.setStatus(NAME, "error")

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
    if not Stats.enabled then return Diagnostics.setStatus(NAME, "off") end
    if thread then return end

    Stats.startedAt = love.timer.getTime()
    loadPending()

    timer = INTERVAL
    clearInflight()
    consecutiveTimeouts = 0
    fatal = false
    Diagnostics.clear(NAME)
    Diagnostics.setStatus(NAME, "connecting")

    spinUpWorker()
end

--- points reporting somewhere other than the live endpoint (a local test
-- server); takes effect for workers started after it
---@param url string
function Stats.setEndpoint(url)
    endpoint = url
end

---@return table|nil # the current failure: { code, detail, count, first, last }
function Stats.lastError()
    return Diagnostics.error(NAME)
end

---@return string|nil # the text a player should paste into a bug report
function Stats.reportText()
    return Diagnostics.reportText(NAME)
end

--- reads replies every frame, and sends at most one request per interval
---@param dt number
function Stats.update(dt)
    if not thread or fatal then return end

    readResults()
    if fatal then return end
    checkWorker()
    if fatal then return end
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
    Diagnostics.clear(NAME)
    Diagnostics.setStatus(NAME, "off")
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
