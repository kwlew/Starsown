local StateManager = require "core.stateManager"
local Presence = require "services.presence"
local Globals = require "globals"

local InGame = {}

function InGame:enter(previousName, opts)
    Presence.set{
        details = "In game",
        state = "Playing",
        smallText = "In game",
        startedAt = Globals.game.startedAt,
    }
end

function InGame:keypressed(key, scancode, isrepeat)
    if key == "escape" then
        StateManager.fadeTo("mainMenu")
    end
end

return InGame