-- src/states/game.lua
-- The main game state.
-- We will have more abstraction behind it.

local StateManager = require "core.stateManager"
local Presence = require "services.presence"
local Globals = require "globals"
local UI = require "ui"
local I18n = require "core.i18n"
local Engine = require "states.game.engine"
local Audio = require "core.audio"

local InGame = {}

--- @param previousName string|nil
--- @param opts? table # { returnTo?: string }
function InGame:enter(previousName, opts)
    Audio.stop("music")
    UI.Music.stop()

    UI.Music.start("game")

    Presence.set{
        details = "Game",
        state = "Playing",
        smallText = "Game",
        startedAt = Globals.game.startedAt,
    }

    self.returnTo = StateManager.returnTarget(previousName, opts, "game")

    Engine:load()
end

function InGame:update(dt)
    Engine:update(dt)
end

function InGame:draw()
    Engine:draw()
end

function InGame:keypressed(key)
    if key == "escape" then
        if Engine:isInventoryOpen() then
            Engine:closeInventory()
        else
            StateManager.fadeTo(self.returnTo)
        end
        return
    end
    Engine:keypressed(key)
end

function InGame:mousepressed(x, y, button)
    Engine:mousepressed(x, y, button)
end

function InGame:wheelmoved(x, y)
    Engine:wheelmoved(x, y)
end

function InGame:keyreleased(key)
    Engine:keyreleased(key)
end

return InGame