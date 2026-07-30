-- src/states/game.lua
-- TODO: implement gameplay. Only the Discord presence and the Esc route to
-- Options exist so far.

local StateManager = require "lib.stateManager"
local Presence = require "lib.presence"
local Globals = require "globals"

local Game = {}

function Game:enter(previousName, opts)
    -- Re-asserted on every entry: the menu we came from set its own presence,
    -- and Options leaves whatever was there in place.
    Presence.set{ details = "In Game", state = "Selecting a level",
                  smallText = "In game", startedAt = Globals.game.startedAt }
end

function Game:keypressed(key)
    if key == "escape" then
        StateManager.fadeTo("options", { returnTo = "game" })
    end
end

return Game