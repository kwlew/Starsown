-- Placeholder for game state.
-- TODO: Implement gameplay state

local StateManager = require "lib.stateManager"
local Audio = require "lib.audio"
local RPC = require "lib.discordRPC"
local UI = require "lib.ui"

local Game = {}

-- Built per-run rather than as a constant (the way the menu's is) because
-- timestamps.start has to be the epoch second this run began — that's what
-- Discord counts its elapsed clock up from, and it must be a number.
function Game:buildPresence()
    return {
        details = "In Game",
        state = "Selecting a level",
        timestamps = { start = self.runStartedAt },
        assets = {
            large_image = "game_logo",
            large_text = "Game",
            small_image = "playing_icon",
            small_text = "In game",
        },
    }
end

-- The RPC connection comes up asynchronously, so the setActivity right after
-- enter() can fail; update() keeps calling this until one lands. Builds the
-- presence itself rather than taking it as an argument — passing it in means
-- update()'s bare call sends nil, which reads as "clear my presence".
function Game:pushPresence()
    if self.presenceSent then return end
    if RPC.isReady() and RPC.setActivity(self:buildPresence()) then
        self.presenceSent = true
    end
end

-- StateManager calls enter(previousName, ...), so the first argument is the
-- state we came from, not a timestamp.
function Game:enter(previousName)
    -- Returning from the pause/options screen continues the same run, so the
    -- elapsed clock keeps counting; arriving from anywhere else starts fresh.
    if previousName ~= "options" or not self.runStartedAt then
        self.runStartedAt = os.time()
    end

    -- Re-assert on every entry: the menu we came from set its own presence,
    -- and Options leaves whatever was there in place.
    self.presenceSent = false
    self:pushPresence()
end

function Game:update(dt)
    self:pushPresence()
end

function Game:keypressed(key)
    if key == "escape" then
        StateManager.fadeTo("options", { returnTo = "game" })
    end
end

return Game