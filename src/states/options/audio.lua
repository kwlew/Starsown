--- Options > Audio: three volume sliders.

local Mixer = require("core.audio.mixer")
local Rows = require("states.options.rows")

local AudioTab = {}
AudioTab.__index = AudioTab

---@param screen table # the Options state
---@return table
function AudioTab.new(screen)
    local self = setmetatable({ name = "audio" }, AudioTab)
    self.volume = Rows.volumeSlider(screen, "volume", love.audio.setVolume, true)
    self.music = Rows.volumeSlider(screen, "musicVolume", function(v) Mixer.setVolume("music", v) end, false)
    self.sfx = Rows.volumeSlider(screen, "sfxVolume", function(v) Mixer.setVolume("sfx", v) end, true)
    self.widgets = { self.volume, self.music, self.sfx }
    return self
end

---@param settings table
function AudioTab:sync(settings)
    self.volume.value = settings.volume
    self.music.value = settings.musicVolume
    self.sfx.value = settings.sfxVolume
end

return AudioTab
