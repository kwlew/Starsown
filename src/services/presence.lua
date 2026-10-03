local Globals = require("globals")
local rpc = require("lib.discordRPC.rpc")
local diagnostics = require("lib.diagnostics")

local Presence = {}

local APP_ID = Globals.services.discordAppId
local NAME = "discord"

local STATUS = {
    disconnected = "waiting for Discord",
    handshaking = "connecting",
    connected = "connected",
}

Presence.SESSION_START = os.time()

local PRESETS = {
    mainMenu     = { details = "Main Menu",    state = "Getting ready", smallText = "In the menu" },
    options      = { details = "Options",      state = "Changing settings" },
    stats        = { details = "Stats",        state = "Viewing stats" },
    achievements = { details = "Achievements", state = "Viewing achievements" },
    game         = { details = "In game",      state = "Playing" },
}

local pending = nil
local pendingKey = nil
local delivered = false
local wasReady = false

function Presence.initialize()
    rpc.initialize(APP_ID, {
        onError = function(code, detail) diagnostics.report(NAME, code, detail) end,
    })
    diagnostics.setStatus(NAME, STATUS.disconnected)
end

function Presence.show(name, overrides)
    local preset = PRESETS[name]
    assert(preset, "Presence.show: no preset named '" .. tostring(name) .. "'")
    overrides = overrides or {}

    local details = overrides.details or preset.details
    local state = overrides.state or preset.state
    local smallText = overrides.smallText or preset.smallText or details
    local startedAt = overrides.startedAt or Presence.SESSION_START

    local key = table.concat({ details, state, smallText, startedAt }, "\0")
    if key == pendingKey then return end

    pending = {
        details = details,
        state = state,
        timestamps = { start = startedAt },
        assets = {
            large_image = "game_logo",
            large_text = Globals.game.name,
            small_image = "playing_icon",
            small_text = smallText,
        },
    }
    pendingKey = key
    delivered = false
end

function Presence.update(dt)
    rpc.update(dt)
    diagnostics.setStatus(NAME, STATUS[rpc.state()] or rpc.state())

    -- a fresh connection (first, or after Discord restarted) shows nothing
    -- until told, so whatever is current has to be sent again
    local ready = rpc.isReady()
    if ready and not wasReady then
        delivered = false
        diagnostics.clear(NAME)
    end
    wasReady = ready

    if delivered or not pending then return end
    if ready and rpc.setActivity(pending) then
        delivered = true
    end
end

function Presence.shutdown()
    rpc.shutdown()
end

return Presence