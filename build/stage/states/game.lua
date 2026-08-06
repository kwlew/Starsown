-- src/states/game.lua
-- TODO: implement gameplay. Only the Discord presence and the Esc route to the
-- pause menu exist so far.

local StateManager = require "lib.stateManager"
local Presence = require "lib.presence"

local Game = {}

local function setPresence()
    Presence.set{ details = "In Game", state = "Selecting a level",
                  smallText = "In game" }
end

-- opts.resumed marks a return from the pause menu rather than the start of a
-- run. Nothing here depends on it yet, but once this state owns a run, `enter`
-- must not rebuild the world on the way back from a pause.
function Game:enter(previousName, opts)
    setPresence()
end

function Game:keypressed(key)
    if key == "escape" then
        -- Pause rather than jumping to Options: the pause menu owns the routes
        -- out of a run now (resume, settings, quit). Instant, so the frozen
        -- frame the menu sits on doesn't fade out from under it.
        StateManager.switch("pause")
    end
end

return Game