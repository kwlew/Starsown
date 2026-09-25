--- Discord Rich Presence. Screens name a preset; this owns the text, the
-- connection and the retry.
--
--   function MainMenu:enter()
--       Presence.show("mainMenu")
--   end
--
-- The IPC connection comes up async a moment after launch, so a setActivity
-- right after a state change can fail. show() records the ask and update()
-- keeps retrying until it lands.
--
-- The title line isn't set from here: Discord always shows the app name from
-- the developer portal and ignores an activity `name`.

local RPC = require "vendor.discordRPC"

local Presence = {}

local APP_ID = "1528201797863473362"

Presence.SESSION_START = os.time()

-- English on purpose: presence is read by the player's Discord friends, not
-- by the player, so the game's language setting says nothing about theirs.
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

--- opens the connection; call once at boot. The handshake finishes async, so
-- nothing is ready yet when this returns.
function Presence.initialize()
    RPC.initialize(APP_ID)
end

--- shows a preset, with any of its fields overridden. Asking for what's
-- already showing is a no-op, so re-entering a screen doesn't spend
-- Discord's setActivity rate limit (~5 per 20s).
---@param name string # a key of PRESETS
---@param overrides? table # { details?: string, state?: string, smallText?: string, startedAt?: integer }; startedAt defaults to the session start
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
            large_text = "Starsown",
            small_image = "playing_icon",
            small_text = smallText,
        },
    }
    pendingKey = key
    delivered = false
end

--- dt matters: RPC.update runs its reconnect backoff off it, so calling this
-- bare freezes the retry timer and a failed connect becomes permanent.
---@param dt number
function Presence.update(dt)
    RPC.update(dt)
    if delivered or not pending then return end
    if RPC.isReady() and RPC.setActivity(pending) then
        delivered = true
    end
end

--- closes the connection; call on quit
function Presence.shutdown()
    RPC.shutdown()
end

return Presence