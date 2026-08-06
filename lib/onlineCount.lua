-- lib/onlineCount.lua
-- Live "players online" figure. Owns the worker thread and the anonymous client
-- ID; screens just read the value:
--
--   if OnlineCount.value then
--       -- draw something with OnlineCount.value
--   end
--
-- value stays nil until the first successful response, and a failed request
-- never clears it. nil means "we don't know yet", and callers draw nothing —
-- rendering a 0 or an error message makes a live game look dead.
--
-- The actual request runs on a thread (lib/threads/onlineCount.lua) because
-- https.request blocks, and on the main thread that would be a visible hitch
-- every heartbeat. See docs/online-player-count.md for the server side.
--
-- Unrelated to lib/presence.lua, which is Discord Rich Presence.

local Json = require "lib.json"

local OnlineCount = {}

local ENDPOINT = "https://tdidle-presence.kwlew.workers.dev/online"
-- Seconds between heartbeats. This is the cost knob: requests/day per player is
-- 86400/INTERVAL, and the server's own window must stay at least 2x this so one
-- dropped request doesn't make a player flicker out of the count.
local INTERVAL = 300
local ID_FILE = "client_id"
local WORKER = "lib/threads/onlineCount.lua"

OnlineCount.value = nil
OnlineCount.enabled = true

local thread, resultChannel, stopChannel

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

-- The worker thread, or nil if its source can't be found.
--
-- newThread resolves a path through love.filesystem, whose root is src/ (the
-- game is launched as `love src` — see .vscode/tasks.json), so lib/ is outside
-- it and the plain path form fails with "Does not exist" in development. What
-- makes `require "lib.onlineCount"` work at all is standard Lua's package.path
-- resolving against the working directory, which is the repo root — so take the
-- same route and hand newThread the source instead of a path.
--
-- love.filesystem is still tried first: in a packaged .love, lib/ is inside the
-- archive where love.filesystem can see it and io.open can't reach it.
local function newWorkerThread()
    if love.filesystem.getInfo(WORKER) then
        return love.thread.newThread(WORKER)
    end

    local path = package.searchpath and package.searchpath("lib.threads.onlineCount", package.path)
        or (love.filesystem.getWorkingDirectory() .. "/" .. WORKER)
    local file = path and io.open(path, "r")
    if not file then return nil end

    local source = file:read("*a")
    file:close()
    -- FileData rather than a bare string so runtime errors in the worker are
    -- reported against its real filename instead of [string "..."].
    return love.thread.newThread(love.filesystem.newFileData(source, WORKER))
end

function OnlineCount.start()
    if thread or not OnlineCount.enabled then return end

    generation = generation + 1
    local resultName = "onlineCount.result." .. generation
    local stopName   = "onlineCount.stop." .. generation

    thread = newWorkerThread()
    -- Nothing to fall back to, and nothing worth interrupting the player over:
    -- the menu simply never shows a figure.
    if not thread then return end

    resultChannel = love.thread.getChannel(resultName)
    stopChannel   = love.thread.getChannel(stopName)

    thread:start(ENDPOINT, clientId(), INTERVAL, resultName, stopName)
end

function OnlineCount.update()
    if not resultChannel then return end

    -- Drain rather than pop once: a stalled frame can leave more than one
    -- response queued, and we only care about the newest.
    local body = resultChannel:pop()
    while body do
        local ok, data = pcall(Json.decode, body)
        if ok and type(data) == "table" and type(data.online) == "number" then
            OnlineCount.value = math.floor(data.online)
        end
        body = resultChannel:pop()
    end
end

function OnlineCount.shutdown()
    if not thread then return end
    -- The thread spends nearly all its life blocked in demand(), so this wakes
    -- it within a frame rather than after a full INTERVAL.
    stopChannel:push(true)
    thread, resultChannel, stopChannel = nil, nil, nil
end

-- Live opt-in/opt-out for the Options toggle. Turning it off has to stop the
-- heartbeat immediately — a privacy switch that waits for a restart isn't one —
-- and clears the value so the menu drops the figure instead of showing a count
-- that is now frozen.
function OnlineCount.setEnabled(enabled)
    if enabled == OnlineCount.enabled then return end
    OnlineCount.enabled = enabled

    if enabled then
        OnlineCount.start()
    else
        OnlineCount.shutdown()
        OnlineCount.value = nil
    end
end

return OnlineCount
