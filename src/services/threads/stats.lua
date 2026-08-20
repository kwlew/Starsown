-- Network half of services/stats.lua, on its own thread: https.request blocks,
-- which on the main thread would be a visible hitch every heartbeat.
--
-- Deliberately dumb: no timer, no counters, no retry policy. It blocks on the
-- job channel, performs exactly the request it's handed, and echoes the
-- payload back with the status code so the main thread decides what a
-- failure means. All state worth keeping lives over there.
--
-- Channel names are passed in, not hardcoded, so a restarted heartbeat can't
-- collide with a thread that hasn't noticed it was stopped (see the
-- generation counter in services/stats.lua).

-- lua-https isn't bundled in the LÖVE 11.5 Windows installer (the .zip has
-- it), and some Linux distro packages strip it too. pcall so a missing
-- module can't crash the thread (which would take the whole game down via
-- love.threaderror) -- missing stats are fine, crashing on launch isn't.
local ok, https = pcall(require, "https")
if not ok then return end

local url, clientId, jobName, resultName = ...

local jobs = love.thread.getChannel(jobName)
local out  = love.thread.getChannel(resultName)

local endpoint = url .. "?id=" .. clientId
local HEADERS = { ["Content-Type"] = "application/json" }

while true do
    -- blocks until there's something to do; main thread pushes "stop" on
    -- shutdown so quitting wakes this within a frame, not after a full interval
    local job = jobs:demand()
    if job == "stop" then break end

    -- pcall: https.request throws on some transport failures instead of
    -- returning a code. No network, bad DNS, TLS error, or 500 all need to
    -- end the same way -- a result with no code, read as "try again later".
    local sent, code, body = pcall(https.request, endpoint, {
        method = "POST",
        data = job.body,
        headers = HEADERS,
    })

    out:push{
        code = sent and code or nil,
        body = sent and body or nil,
        stars = job.stars,
        golden = job.golden,
        rainbow = job.rainbow,
    }
end
