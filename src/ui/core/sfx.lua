-- src/ui/sfx.lua
-- Helper for the sfx in the game.

local Audio = require "core.audio"
local Audios = require "utils.audios"

local Sfx = {}

-- Moving focus.
local FOCUS_VOLUME = 0.40
-- Selecting a menu item.
local SELECT_VOLUME = 0.50


-- Committing something: a menu choice, a settings change, a tab switch.
function Sfx.select()
    Audio.play("sfx", Audios.clone("menuButton3"), { volume = SELECT_VOLUME })
end

-- Pressing a control that opens something: a dialog, a link, Apply.
function Sfx.press()
    Audio.play("sfx", Audios.clone("menuBeep"))
end

-- Moving the focus between rows.
function Sfx.focus()
    Audio.play("sfx", Audios.clone("menuButton4"), { volume = FOCUS_VOLUME })
end

return Sfx
