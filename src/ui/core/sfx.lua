--- The UI's feedback sounds, by meaning rather than by file. The UI only
-- says what happened; whoever owns audio decides what it sounds like:
--
--   Sfx.setPlayer(function(cue) Audio.play("sfx", Audios.clone(CLIPS[cue])) end)
--
-- Until a player is set every cue is silent, so the UI never depends on the
-- audio system being up.

local Sfx = {}

---@alias SfxCue "select"|"press"|"focus"

local player = nil

---@param fn? fun(cue: SfxCue) # nil silences every cue
function Sfx.setPlayer(fn)
    player = fn
end

---@param cue SfxCue
local function play(cue)
    if player then player(cue) end
end

--- committing something: a menu choice, a settings change, a tab switch
function Sfx.select() play("select") end

--- pressing a control that opens something: a dialog, a link, Apply
function Sfx.press() play("press") end

--- moving focus between rows
function Sfx.focus() play("focus") end

return Sfx
