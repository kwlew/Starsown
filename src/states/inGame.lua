local StateManager = require "core.stateManager"
local Presence = require "services.presence"

local InGame = {}

function InGame:enter(previousName, opts)
    if previousName == "mainMenu" or not self.runStartedAt then
        self.runStartedAt = os.time()
    end
    Presence.show("game", { startedAt = self.runStartedAt })
end

function InGame:keypressed(key, scancode, isrepeat)
    if key == "escape" then
        StateManager.fadeTo("mainMenu")
    end
end

return InGame
