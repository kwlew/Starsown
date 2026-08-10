-- src/services/threads/stats.lua
-- The network half of src/services/stats.lua, on its own thread: https.request blocks,
-- and on the main thread that would be a visible hitch every heartbeat.
--
-- Deliberately dumb. It holds no timer, no counters and no retry policy — it
-- blocks on the job channel, performs exactly the request it is handed, and
-- echoes the payload back with the status code so the main thread can decide
-- what a failure means. All of the state that would be painful to lose lives
-- over there, where it can be written to disk on quit.
--
-- Channel names are passed in rather than hardcoded so a restarted heartbeat
-- can't collide with a thread that hasn't noticed it was stopped yet — see the
-- generation counter in src/services/stats.lua.

-- pcall, because an uncaught error on a thread reaches love.threaderror and
-- takes the whole game down with it — and lua-https is not as guaranteed as it
-- looks. The LÖVE 11.5 Windows *installer* ships no https.dll (the .zip does),
-- and some Linux distro packages strip the module too. Missing counters are
-- fine; crashing on launch over one is not. Exiting here leaves every value
-- nil, which every screen already treats as "draw nothing".
local ok, https = pcall(require, "https")
if not ok then return end

local url, clientId, jobName, resultName = ...

local jobs = love.thread.getChannel(jobName)
local out  = love.thread.getChannel(resultName)

local endpoint = url .. "?id=" .. clientId
local HEADERS = { ["Content-Type"] = "application/json" }

while true do
    -- Blocks until there is something to do. The main thread pushes "stop" on
    -- shutdown, so quitting or switching the option off wakes this within a
    -- frame instead of waiting out an interval.
    local job = jobs:demand()
    if job == "stop" then break end

    -- pcall because https.request throws on some transport failures rather than
    -- returning a code. No network, bad DNS, a TLS error, or a 500 must all end
    -- the same way: a result with no code, which the main thread reads as
    -- "try again later". Nothing here is ever allowed to reach the game.
    local sent, code, body = pcall(https.request, endpoint, {
        method = "POST",
        data = job.body,
        headers = HEADERS,
    })

    -- The counts ride back out with the response: the main thread put them
    -- in flight and needs them returned to know what to re-queue.
    out:push{
        code = sent and code or nil,
        body = sent and body or nil,
        stars = job.stars,
        golden = job.golden,
    }
end
