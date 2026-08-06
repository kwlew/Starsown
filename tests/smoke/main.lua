-- tests/smoke/main.lua
-- Boots the *packaged* game inside a real LÖVE, runs it for a few seconds, and
-- exits non-zero if anything went wrong. This is the only test that touches the
-- engine: fonts, shaders, audio sources, threads and the state machine all get
-- constructed for real, which is where the failures the unit tests cannot see
-- live -- a renamed asset, a missing require, a state that throws on enter.
--
-- Run it with tools/smoke.sh; it expects the .love next to this file as
-- `game.love` and mounts it at the filesystem root, so the game sees exactly
-- the paths it would see if LÖVE had opened the archive itself.
--
-- Why not just run the archive directly? Because the game never quits on its
-- own, and a Lua error inside LÖVE opens the blue error screen and waits
-- forever instead of returning a failing exit code. Wrapping it is what turns
-- "it booted" into a pass/fail.

local ARCHIVE  = "game.love"
local SECONDS  = tonumber(os.getenv("SMOKE_SECONDS") or "") or 5
local MIN_FRAMES = tonumber(os.getenv("SMOKE_MIN_FRAMES") or "") or 60

local function say(message)
    io.stdout:write("[smoke] " .. message .. "\n")
    io.stdout:flush()
end

local function die(message)
    io.stderr:write("[smoke] FAIL: " .. message .. "\n")
    io.stderr:flush()
    os.exit(1)
end

-- Replaces LÖVE's error screen, which would otherwise swallow the failure and
-- sit at a blue screen until the CI job's timeout kills it.
local function errorhandler(message)
    io.stderr:write("[smoke] FAIL: unhandled error\n")
    io.stderr:write(tostring(message) .. "\n")
    io.stderr:write(debug.traceback("", 2) .. "\n")
    io.stderr:flush()
    os.exit(1)
end

love.errorhandler = errorhandler
love.errhand = errorhandler -- LÖVE 11.3 and older

-- A thread that dies takes the game down through this, and the online-count
-- heartbeat runs on one.
function love.threaderror(_, message)
    die("a thread errored: " .. tostring(message))
end

--------------------------------------------------------------------------------
-- Mount the package
--------------------------------------------------------------------------------

if not love.filesystem.getInfo(ARCHIVE) then
    die(ARCHIVE .. " is not next to the harness -- build it with tools/package.sh first")
end

-- love.filesystem.mount only resolves archives inside the save directory, so
-- the .love has to be copied there first. (It sits next to the harness, in the
-- game directory, which mount will not look in.)
local MOUNTED = "mounted.love"
local archiveData = love.filesystem.read(ARCHIVE)
if not archiveData then die("could not read " .. ARCHIVE) end
if not love.filesystem.write(MOUNTED, archiveData) then
    die("could not stage " .. ARCHIVE .. " in the save directory")
end
archiveData = nil

-- Mounted at "" so the archive *is* the root: the game's own "assets/lang/..."
-- and require "lib.settings" resolve without knowing they were packaged.
if not love.filesystem.mount(MOUNTED, "") then
    die("could not mount " .. ARCHIVE .. " (is it a valid zip?)")
end

for _, required in ipairs({ "main.lua", "conf.lua" }) do
    if not love.filesystem.getInfo(required) then
        die(required .. " is missing from the archive root")
    end
end

--------------------------------------------------------------------------------
-- Exercise the game's conf.lua
--------------------------------------------------------------------------------

-- LÖVE ran the harness's conf.lua, not the game's, so the real one is checked
-- here by hand: it is the file that reads the saved settings and hands them to
-- window creation, and a failure in it is a game that never opens a window.
-- The window is NOT reconfigured from the result -- only the code path is
-- exercised, and the identity it sets is put back afterwards so nothing here
-- can write into the player's real save directory.
do
    local previousIdentity = love.filesystem.getIdentity()
    local gameConf = love.filesystem.load("conf.lua")
    if not gameConf then die("conf.lua does not compile") end

    local previousConf = love.conf
    gameConf()
    if type(love.conf) ~= "function" then die("conf.lua did not define love.conf") end

    local t = { window = {}, modules = {}, audio = {} }
    local ok, err = pcall(love.conf, t)
    love.conf = previousConf
    love.filesystem.setIdentity(previousIdentity)

    if not ok then die("love.conf raised: " .. tostring(err)) end
    if type(t.window.width) ~= "number" or t.window.width <= 0 then
        die("love.conf left an unusable window width")
    end
    if type(t.identity) ~= "string" or t.identity == "" then
        die("love.conf left no save identity")
    end
    say(("conf ok (%dx%d, msaa %s, vsync %s)"):format(
        t.window.width, t.window.height, tostring(t.window.msaa), tostring(t.window.vsync)))
end

--------------------------------------------------------------------------------
-- Boot the game
--------------------------------------------------------------------------------

local chunk, err = love.filesystem.load("main.lua")
if not chunk then die("main.lua does not compile: " .. tostring(err)) end
chunk() -- defines love.load/update/draw/... over the harness's

local gameLoad, gameUpdate, gameDraw = love.load, love.update, love.draw
if type(gameLoad) ~= "function" then die("the game defined no love.load") end
if type(gameUpdate) ~= "function" then die("the game defined no love.update") end
if type(gameDraw) ~= "function" then die("the game defined no love.draw") end

local loaded, frames, draws = false, 0, 0
local startedAt

function love.load(...)
    gameLoad(...)
    loaded = true
    startedAt = love.timer.getTime()
    say("love.load returned")
end

function love.update(dt)
    gameUpdate(dt)
    frames = frames + 1
    -- Both bounds have to be met: a fast machine would otherwise blow through
    -- the seconds before the loading screen has drawn anything at all.
    if frames >= MIN_FRAMES and (love.timer.getTime() - startedAt) >= SECONDS then
        love.event.quit()
    end
end

function love.draw()
    gameDraw()
    draws = draws + 1
end

-- The game's own love.quit does the Discord/heartbeat teardown; it must run,
-- and it must not throw.
local gameQuit = love.quit
function love.quit()
    if gameQuit then gameQuit() end
    if not loaded then die("love.load never ran") end
    if draws == 0 then die("the game never drew a frame") end

    love.filesystem.unmount(MOUNTED)
    love.filesystem.remove(MOUNTED) -- don't leave 2MB in the save directory

    say(("PASS -- %d frames, %d draws in %.1fs"):format(
        frames, draws, love.timer.getTime() - startedAt))
end
