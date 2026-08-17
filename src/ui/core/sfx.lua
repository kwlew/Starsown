-- src/ui/sfx.lua
-- The UI's three sounds, so a screen names the event instead of naming a clip,
-- a channel and a volume. A clip that failed to preload arrives as nil and
-- Audio.play already tolerates it.

local Audio = require "core.audio"
local Audios = require "utils.audios"

local Sfx = {}

-- The focus blip fires on every arrow press, so it sits well under a selection:
-- at full volume, holding a direction reads as a rattle.
local FOCUS_VOLUME = 0.15

-- Committing something: a menu choice, a settings change, a tab switch.
function Sfx.select()
    Audio.play("sfx", Audios.clone("menuBlipSelect2"))
end

-- Pressing a control that opens something: a dialog, a link, Apply.
function Sfx.press()
    Audio.play("sfx", Audios.clone("menuBlipSelect"))
end

-- Moving the focus between rows.
function Sfx.focus()
    Audio.play("sfx", Audios.clone("menuBlipSelect"), { volume = FOCUS_VOLUME })
end

return Sfx
