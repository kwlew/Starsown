local StateManager = require "core.stateManager"
local Settings = require "core.settings"
local Assets = require "core.assets"

local Globals = require "globals"

local Presence = require "services.presence"

local UI = require "ui"
local I18n = require "core.i18n"

local Audio = require "core.audio"
local Audios = require "utils.audios"

local Achievements = {}

local function setPresence()
    Presence.set{
        details = "Achievements",
        state = "Viewing achievements",
        smallText = "Achievements",
        startedAt = Globals.game.startedAt,
    }
end

function Achievements:enter(previousName, opts)
    -- Initialize the achievements state
    setPresence()

    self.returnTo = StateManager.returnTarget(previousName, opts, "achievements")
end

function Achievements:leave()
    UI.Sfx.select()
    StateManager.fadeTo(self.returnTo)

end

function Achievements:keypressed(key)
    if key == "escape" then
        self:leave()
    end
end

return Achievements