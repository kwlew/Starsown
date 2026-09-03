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

--- what Discord shows while this screen is up
local function setPresence()
    Presence.set{
        details = "Achievements",
        state = "Viewing achievements",
        smallText = "Achievements",
        startedAt = Globals.game.startedAt,
    }
end

--- no content yet: this registers and remembers where back goes, but the
-- screen has no draw/update of its own
---@param previousName string|nil
---@param opts? table # { returnTo?: string }
function Achievements:enter(previousName, opts)
    setPresence()

    self.returnTo = StateManager.returnTarget(previousName, opts, "achievements")
end

--- fades back to whichever screen opened this one
function Achievements:leave()
    UI.Sfx.select()
    StateManager.fadeTo(self.returnTo)

end

---@param key string
function Achievements:keypressed(key)
    if key == "escape" then
        self:leave()
    end
end

return Achievements