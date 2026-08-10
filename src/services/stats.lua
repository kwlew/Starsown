-- src/services/stats.lua
-- The shared, world-wide numbers: how many people are playing right now, and
-- how many shooting stars have been popped since the game existed. Owns the
-- worker thread, the anonymous client ID, and the opt-out. Screens just read:
--
--   if Stats.online then -- draw something with Stats.online end
--   if Stats.stars  then -- ...and with Stats.stars / Stats.golden end
--
-- and anything that pops a star calls:
--
--   Stats.pop(isGolden)
--
-- Every value stays nil until the first successful response, and a failed
-- request never clears one. nil means "we don't know yet", and callers draw
-- nothing — rendering a 0 or an error message makes a live game look dead.
--
-- One request carries everything. Pops are accumulated locally and ride out on
-- the same heartbeat that reports presence, so clicking stars costs no extra
-- traffic at all; see docs/shared-stats.md for the server side.
--
-- Succeeds the older onlineCount module. Unrelated to src/services/presence.lua,
-- which is Discord Rich Presence.

local Json = require "vendor.json"

local Stats = {}

local ENDPOINT = "https://tdidle-presence.kwlew.workers.dev/stats"
-- Seconds between heartbeats. This is the cost knob: requests/day per player is
-- 86400/INTERVAL, and the server's own window must stay at least 2x this so one
-- dropped request doesn't make a player flicker out of the count.
local INTERVAL = 60
local ID_FILE = "client_id"
local PENDING_FILE = "stats_pending"
-- Resolved through love.filesystem, whose root is src/ — so this is relative to
-- src/, not to the repo.
local WORKER = "services/threads/stats.lua"

-- Stars per request the server will accept. Anything above this is rejected
-- outright, so a backlog has to go out in chunks rather than in one refused
-- lump. Kept in step with MAX_REPORT in the worker.
local MAX_REPORT = 400

-- Ceiling on the backlog itself. Reaching this means either a very long session
-- with no network or something that is not a player, and either way there is no
-- point growing a number the server will spend hours draining.
local MAX_PENDING = 5000

-- Every value the screens read. nil until the server says otherwise.
Stats.online = nil
Stats.stars = nil
Stats.golden = nil
Stats.enabled = true

local thread, jobChannel, resultChannel
local timer = INTERVAL -- fire the first heartbeat immediately, not in 5 minutes
local loadedPending = false

-- Pops waiting to be sent, and the ones currently on the wire. Split so a
-- request that fails can put exactly what it took back, without swallowing
-- anything that was popped while it was in flight.
local pending = { stars = 0, golden = 0 }
local inflight = nil

-- Bumped on every start so each thread gets its own pair of channels. Reusing
-- one shared channel meant a thread that was still finishing a request when we
-- restarted could swallow the new thread's stop token (leaking the old thread
-- forever) or push a stale count into the new one. Private names per generation
-- make both impossible without blocking the main thread on a join.
local generation = 0

-- A random v4 UUID. Not derived from hardware, username, or anything else about
-- the player: it exists only so the server can tell two running copies apart.
local function uuid()
    -- love.math's default seed is not guaranteed to differ between installs,
    -- and two players sharing an ID would undercount.
    love.math.setRandomSeed(os.time() + math.floor(os.clock() * 1000000))
    return (("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"):gsub("[xy]", function(c)
        local v = (c == "x") and love.math.random(0, 15) or love.math.random(8, 11)
        return string.format("%x", v)
    end))
end

-- The stable per-install ID, generated once and kept next to settings.lua.
-- >= and not >: a UUID is exactly 36 characters, so a > test rejects every ID
-- we ever wrote and mints a fresh one on each launch — which reads to the
-- server as a brand new player every time and inflates the count.
local function clientId()
    local saved = love.filesystem.read(ID_FILE)
    if saved and #saved >= 36 then return saved:sub(1, 36) end
    local id = uuid()
    love.filesystem.write(ID_FILE, id)
    return id
end

-- Pops that never made it out before the game closed. Without this, quitting
-- inside the heartbeat window — which is most sessions, since the menu is where
-- the stars are — would drop every star that session popped.
--
-- Read once and deleted immediately: the backlog is authoritative in memory
-- from here on, and a file left on disk would be counted again on the next
-- launch if we crashed before rewriting it.
local function loadPending()
    -- Guards savePending below: a session that never started the heartbeat has
    -- not read the file, and must not rewrite (or delete) a backlog it knows
    -- nothing about.
    loadedPending = true

    local saved = love.filesystem.read(PENDING_FILE)
    if not saved then return end
    love.filesystem.remove(PENDING_FILE)

    local stars, golden = saved:match("^(%d+)%s+(%d+)")
    stars, golden = tonumber(stars), tonumber(golden)
    -- A hand-edited or truncated file is not worth a crash, and not worth
    -- trusting either.
    if not stars or not golden or golden > stars then return end

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

-- The worker thread, or nil if its source can't be found.
--
-- This used to carry a fallback that read the worker off the real filesystem
-- with io.open and handed newThread the source, because the worker lived in
-- lib/ — outside love.filesystem's root, and so invisible to newThread. It
-- never rescued a packaged build either: a .love built from src/ didn't contain
-- lib/ at all and died on the first require in main.lua. The worker lives under
-- src/ now, so the plain path form works in development and in a .love alike.
local function newWorkerThread()
    if not love.filesystem.getInfo(WORKER) then return nil end
    return love.thread.newThread(WORKER)
end

-- Moves a chunk of the backlog onto the wire. Chunked because the server caps a
-- single report, and an over-cap report is refused rather than clamped — so a
-- backlog sent whole would be rejected whole, forever.
local function dispatch()
    local stars = math.min(pending.stars, MAX_REPORT)
    local golden = math.min(pending.golden, stars)

    pending.stars = pending.stars - stars
    pending.golden = pending.golden - golden
    inflight = { stars = stars, golden = golden }

    -- Hand-rolled rather than Json.encode: the payload is two integers, and
    -- this way the worker needs no module of ours at all, which keeps it
    -- independent of how the rest of the tree is laid out.
    jobChannel:push{
        body = ('{"stars":%d,"golden":%d}'):format(stars, golden),
        stars = stars,
        golden = golden,
    }
end

-- Puts a failed report's counts back at the front of the backlog.
local function requeue(stars, golden)
    pending.stars = math.min(pending.stars + stars, MAX_PENDING)
    pending.golden = math.min(pending.golden + golden, pending.stars)
end

-- Is this status code worth sending the same payload again for?
--
-- A 4xx other than 429 means the server has judged this payload unacceptable,
-- and will judge an identical one exactly the same way — retrying it forever
-- would wedge every pop behind it. Everything else (no code at all, a 5xx, a
-- 429) is a "later", not a "no".
local function retryable(code)
    if not code then return true end
    return code < 400 or code >= 500 or code == 429
end

local function readResults()
    if not resultChannel then return end

    -- Drain rather than pop once: a stalled frame can leave more than one
    -- response queued, and only the newest numbers matter.
    local result = resultChannel:pop()
    while result do
        -- Answered either way, so nothing is on the wire any more; whether the
        -- counts go back into the backlog is the next question, not this one.
        inflight = nil

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
    -- Nothing to fall back to, and nothing worth interrupting the player over:
    -- the menu simply never shows a figure.
    if not thread then return end

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
    -- One request at a time. A second one while the first is unanswered would
    -- report the same backlog twice if the first turned out to have landed.
    if inflight then return end

    timer = 0
    dispatch()
end

-- Records one popped star. Cheap enough to call straight from a click handler:
-- it moves two integers and never touches the network.
function Stats.pop(golden)
    if not Stats.enabled then return end
    if pending.stars >= MAX_PENDING then return end

    pending.stars = pending.stars + 1
    if golden then pending.golden = pending.golden + 1 end
end

function Stats.shutdown()
    -- Read whatever came back before deciding what is unsent, or a report that
    -- succeeded in the last few frames gets counted a second time next launch.
    readResults()
    if inflight then
        requeue(inflight.stars, inflight.golden)
        inflight = nil
    end
    -- Before the early return: with no https module there is no thread, but
    -- there is still a backlog, and it should survive until the player has a
    -- build that can send it.
    savePending()

    if not thread then return end

    -- The thread spends nearly all its life blocked in demand(), so this wakes
    -- it within a frame rather than after a full request.
    jobChannel:push("stop")
    thread, jobChannel, resultChannel = nil, nil, nil
end

-- Live opt-in/opt-out for the Options toggle. Turning it off has to stop the
-- heartbeat immediately — a privacy switch that waits for a restart isn't one —
-- and drops every value so the menu stops showing figures that are now frozen.
function Stats.setEnabled(enabled)
    if enabled == Stats.enabled then return end
    Stats.enabled = enabled

    if enabled then
        Stats.start()
        return
    end

    Stats.shutdown()
    Stats.online, Stats.stars, Stats.golden = nil, nil, nil
    -- Opting out means opting out of the backlog too: holding unsent pops on
    -- disk for a player who asked us to stop reporting them would send them the
    -- moment they changed their mind, which is not what the switch promises.
    pending.stars, pending.golden = 0, 0
    love.filesystem.remove(PENDING_FILE)
end

return Stats
