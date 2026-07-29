-- src/states/game.lua
-- TODO: implement gameplay. Only the Discord presence and the Esc route to
-- Options exist so far.

local StateManager = require "lib.stateManager"
local Presence = require "lib.presence"

local Game = {}

function Game:enter(previousName, opts)
    -- Returning from the pause/options screen continues the same run, so the
    -- elapsed clock keeps counting; arriving from anywhere else starts fresh.
    if previousName ~= "options" or not self.runStartedAt then
        self.runStartedAt = (type(opts) == "table" and opts.startedAt) or os.time()
    end

    -- Re-asserted on every entry: the menu we came from set its own presence,
    -- and Options leaves whatever was there in place.
    Presence.set{ details = "In Game", state = "Selecting a level",
                  smallText = "In game", startedAt = self.runStartedAt }
end

function Game:keypressed(key)
    if key == "escape" then
        StateManager.fadeTo("options", { returnTo = "game" })
    end
end

return Game