--- One-shot sounds by meaning, mapped to preloaded clips.

local Library = require("core.audio.library")
local Math = require("utils.math")
local Mixer = require("core.audio.mixer")

local Sounds = {}

local UI_CUES = {
    select = { clip = "menuButton3", volume = 0.50 },
    press = { clip = "menuBeep", volume = 1 },
    focus = { clip = "menuButton4", volume = 0.40 },
}

local STAR_POPS = { "starExplosion", "starExplosion2", "starExplosion3" }
local STAR_POP_VOLUME = 0.50

---@param name string
---@param volume number
local function play(name, volume)
    Mixer.play("sfx", Library.clone(name), { volume = volume })
end

--- plays a UI feedback cue; plug into UI.Sfx.setPlayer
---@param cue string
function Sounds.ui(cue)
    local sound = UI_CUES[cue]
    if sound then play(sound.clip, sound.volume) end
end

---@param golden boolean
function Sounds.starPop(golden)
    local clip = golden and "goldenStarExplosion" or STAR_POPS[Math.randInt(1, #STAR_POPS)]
    play(clip, STAR_POP_VOLUME)
end

return Sounds
