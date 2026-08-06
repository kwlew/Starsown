-- lib/threads/onlineCount.lua
-- The online-player heartbeat, on its own thread: https.request blocks, and on
-- the main thread that would be a visible hitch every INTERVAL seconds.
-- Results go back over a channel; lib/onlineCount.lua drains them from update.
--
-- Channel names are passed in rather than hardcoded so a restarted heartbeat
-- can't collide with a thread that hasn't noticed it was stopped yet — see the
-- generation counter in lib/onlineCount.lua.
--
-- Threads start with only the base `love` table, so love.timer has to be
-- required here even though main.lua already uses it.

-- pcall, because an uncaught error on a thread reaches love.threaderror and
-- takes the whole game down with it — and lua-https is not as guaranteed as it
-- looks. The LÖVE 11.5 Windows *installer* ships no https.dll (the .zip does),
-- and some Linux distro packages strip the module too. A missing counter is
-- fine; crashing on launch over one is not. Exiting here leaves the count nil,
-- which every screen already treats as "draw nothing".
local ok, https = pcall(require, "https")
if not ok then return end

require "love.timer"

local url, clientId, interval, resultName, stopName = ...

local out  = love.thread.getChannel(resultName)
local stop = love.thread.getChannel(stopName)

local endpoint = url .. "?id=" .. clientId

while true do
    -- pcall because https.request throws on some transport failures rather than
    -- returning a code. No network, bad DNS, a TLS error, or a 500 must all end
    -- the same way: nothing pushed, try again next interval, player sees no
    -- change. Nothing here is ever allowed to reach the game.
    local ok, code, body = pcall(https.request, endpoint)
    if ok and code == 200 and body then
        out:push(body)
    end

    -- demand() doubles as the sleep: it blocks for `interval` seconds, but
    -- returns the moment shutdown() pushes, so quitting or switching the option
    -- off doesn't wait out the rest of the heartbeat.
    if stop:demand(interval) ~= nil then break end
end
