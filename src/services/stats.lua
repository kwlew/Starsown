--- Anonymous world stats: reports popped stars, reads back world totals.
-- Counters stay nil until the first successful reply.

local Backlog = require("services.stats.backlog")
local ClientId = require("services.stats.clientId")
local Diagnostics = require("lib.diagnostics")
local Globals = require("globals")
local Https = require("services.stats.https")
local Reply = require("services.stats.reply")
local Consent = require("services.consent")
local Worker = require("services.stats.worker")

local Stats = {
    enabled = true,
    online = nil,
    stars = nil,
    golden = nil,
    rainbow = nil,
    startedAt = nil,
    lastUpdated = nil,
}

local NAME = "stats"
local INTERVAL = 5           -- seconds between reports
local MAX_REPORT = 400       -- stars per request
local TIMEOUT = 10           -- seconds before a request counts as lost
local MAX_INTERVAL = 180     -- backoff ceiling after repeated timeouts

local endpoint = Globals.services.statsEndpoint
local timer = INTERVAL
local inflight, sentAt = nil, nil
local timeouts = 0
local fatal = false -- retrying can't fix it; stop until restarted

---@param status string
---@param code? string
---@param detail? any
local function setStatus(status, code, detail)
    if code then Diagnostics.report(NAME, code, detail) end
    Diagnostics.setStatus(NAME, status)
end

---@param code string
---@param detail any
local function fail(code, detail)
    fatal = true
    setStatus("error", code, detail)
end

local function startWorker()
    local ok, err = Worker.start(endpoint, ClientId.get(), Https.cpath())
    if not ok then fail("ST-NOWORKER", err) end
end

---@param totals table
local function applyTotals(totals)
    for key, value in pairs(totals) do Stats[key] = value end
    Stats.lastUpdated = love.timer.getTime()
    Diagnostics.clear(NAME)
    setStatus("ok")
end

---@param result table
local function handle(result)
    local outcome = Reply.read(result)
    if outcome.fatal then return fail(outcome.fatal, outcome.detail) end

    inflight, sentAt, timeouts = nil, nil, 0
    if outcome.totals then return applyTotals(outcome.totals) end
    if outcome.retry and result.report then Backlog.putBack(result.report) end
    setStatus("error", outcome.error, outcome.detail)
end

local function readReplies()
    local result = Worker.poll()
    while result and not fatal do
        handle(result)
        result = Worker.poll()
    end
end

--- requeues a lost request and replaces the stuck thread
local function checkTimeout()
    if not inflight or love.timer.getTime() - sentAt < TIMEOUT then return end
    Backlog.putBack(inflight)
    inflight, sentAt = nil, nil
    timeouts = timeouts + 1
    setStatus("error", "ST-TIMEOUT", ("no reply from %s within %ds"):format(endpoint, TIMEOUT))
    startWorker()
end

local function dispatch()
    local report = Backlog.take(MAX_REPORT)
    inflight, sentAt = report, love.timer.getTime()
    Worker.send{
        body = ('{"stars":%d,"golden":%d,"rainbow":%d}'):format(report.stars, report.golden, report.rainbow),
        report = report,
    }
end

---@return number
local function interval()
    return math.min(INTERVAL * 2 ^ timeouts, MAX_INTERVAL)
end

function Stats.start()
    if not Stats.enabled then return setStatus("off") end
    if Worker.isStarted() then return end

    Stats.startedAt = love.timer.getTime()
    Backlog.load()
    timer, inflight, sentAt, timeouts, fatal = INTERVAL, nil, nil, 0, false
    Diagnostics.clear(NAME)
    setStatus("connecting")
    startWorker()
end

---@param dt number
function Stats.update(dt)
    if not Worker.isStarted() or fatal then return end

    readReplies()
    if fatal then return end
    local crash = Worker.failure()
    if crash then
        readReplies() -- it may have explained itself first
        if not fatal then fail("ST-CRASH", crash) end
        return
    end
    checkTimeout()

    timer = timer + dt
    if timer < interval() or inflight then return end
    timer = 0
    dispatch()
end

--- counts one popped star toward the next report
---@param kind? "golden"|"rainbow"
function Stats.pop(kind)
    if Stats.enabled then Backlog.add(kind) end
end

--- saves anything undelivered and stops the thread
function Stats.shutdown()
    readReplies()
    if inflight then
        Backlog.putBack(inflight)
        inflight, sentAt = nil, nil
    end
    Backlog.save()
    Worker.stop()
end

local function forgetEverything()
    Stats.online, Stats.stars, Stats.golden, Stats.rainbow = nil, nil, nil, nil
    Stats.startedAt, Stats.lastUpdated = nil, nil
    Backlog.clear()
    ClientId.forget()
end

--- turning it off also deletes local stats data
---@param enabled boolean
function Stats.setEnabled(enabled)
    if enabled == Stats.enabled then
        if not enabled then forgetEverything() end
        return
    end
    Stats.enabled = enabled
    if enabled then return Stats.start() end

    Stats.shutdown()
    forgetEverything()
    Diagnostics.clear(NAME)
    setStatus("off")
end

--- the player answered the consent question
---@param settings table
---@param enabled boolean
function Stats.setConsent(settings, enabled)
    Consent.record(settings, "shareStats", "statsConsentAsked", enabled)
    Stats.setEnabled(enabled)
end

---@param url string # e.g. a local test server
function Stats.setEndpoint(url)
    endpoint = url
end

Stats.checkHttps = Https.check

---@return table|nil # { code, detail, count, first, last }
function Stats.lastError()
    return Diagnostics.error(NAME)
end

---@return string
function Stats.reportText()
    return Diagnostics.reportText(NAME)
end

return Stats
