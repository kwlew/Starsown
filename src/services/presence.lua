-- Discord Rich Presence. Screens declare what should be shown; this owns the
-- connection and the retry.
--
--   function MainMenu:enter()
--       Presence.set{ details = "Main Menu", state = "Getting ready",
--                     smallText = "In the menu" }
--   end
--
-- The IPC connection comes up async a moment after launch, so a setActivity
-- right after a state change can fail. set() records the ask and update()
-- keeps retrying until it lands.
--
-- The title line isn't set from here: Discord always shows the app name from
-- the developer portal and ignores an activity `name`.

local RPC = require "vendor.discordRPC"

local Presence = {}

local APP_ID = "1528201797863473362"

-- Discord's elapsed clock counts up from timestamps.start; this is the
-- default epoch for screens that belong to the whole session (the menu). A
-- screen with its own clock (a gameplay run) passes startedAt.
Presence.SESSION_START = os.time()

local pending = nil
local delivered = false

function Presence.initialize()
    RPC.initialize(APP_ID)
end

function Presence.set(opts)
    pending = {
        details = opts.details,
        state = opts.state,
        timestamps = { start = opts.startedAt or Presence.SESSION_START },
        assets = {
            large_image = "game_logo",
            large_text = "TD Idle",
            small_image = "playing_icon",
            small_text = opts.smallText or opts.details,
        },
    }
    delivered = false
end

-- dt matters: RPC.update runs its reconnect backoff off it, so calling this
-- bare freezes the retry timer and a failed connect becomes permanent.
function Presence.update(dt)
    RPC.update(dt)
    if delivered or not pending then return end
    if RPC.isReady() and RPC.setActivity(pending) then
        delivered = true
    end
end

function Presence.shutdown()
    RPC.shutdown()
end

return Presence
