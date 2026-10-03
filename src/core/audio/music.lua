--- Background music: random tracks from a playlist, crossfaded forever.
--
--   Music.start("menu")   -- no-op if already playing that playlist
--   Music.update(dt)      -- every frame, from main.lua

local Library = require("core.audio.library")
local Math = require("utils.math")
local Mixer = require("core.audio.mixer")

local Music = {}

local PLAYLISTS = {
    menu = { "mainMenuBG", "mainMenuBG2", "mainMenuBG3" },
    game = { "forest", "StarryNight", "Snowfall" },
}

local CROSSFADE = 4 -- seconds
local FADE_IN = 1.5 -- seconds, the session's first track

local current = nil -- { source, name, level? }
local incoming = nil -- { source, name, fade }, during a crossfade
local introFade = 1
local playlist = "menu"

--- never repeats the track just played, when there's a choice
---@param exclude string|nil
---@return string
local function pickTrack(exclude)
    local tracks = PLAYLISTS[playlist]
    if #tracks <= 1 then return tracks[1] end
    local name
    repeat name = tracks[Math.randInt(1, #tracks)] until name ~= exclude
    return name
end

---@param name string
---@param volume number
---@return table|nil
local function playTrack(name, volume)
    local source = Library.get(name)
    if not source then return nil end
    Mixer.play("music", source, { loop = false })
    source:setVolume(volume)
    return { source = source, name = name }
end

---@param from table
local function beginCrossfade(from)
    incoming = playTrack(pickTrack(from.name), 0)
    if incoming then incoming.fade = 0 end
end

---@param kind "menu"|"game"
function Music.start(kind)
    assert(PLAYLISTS[kind], "Music.start: no playlist named '" .. tostring(kind) .. "'")
    local isPlaying = current and current.source:isPlaying()
    if isPlaying and kind == playlist then return end
    playlist = kind

    if not isPlaying then
        current = playTrack(pickTrack(current and current.name), 0)
        introFade = 0
        return
    end

    if incoming then -- already crossfading: promote it, fade out from there
        Mixer.stop("music", current.source)
        current, incoming = incoming, nil
        current.level = current.fade
    end
    beginCrossfade(current)
end

--- forgets the current track without stopping it
function Music.stop()
    current, incoming = nil, nil
end

---@param dt number
function Music.update(dt)
    if not current then return end
    local volume = Mixer.getVolume("music")
    introFade = math.min(1, introFade + dt / FADE_IN)

    if incoming then
        incoming.fade = math.min(1, incoming.fade + dt / CROSSFADE)
        incoming.source:setVolume(volume * incoming.fade)
        current.source:setVolume(volume * (current.level or 1) * (1 - incoming.fade) * introFade)
        if incoming.fade >= 1 or not current.source:isPlaying() then
            Mixer.stop("music", current.source)
            current, incoming = incoming, nil
        end
        return
    end

    current.source:setVolume(volume * introFade)
    if not current.source:isPlaying() then
        current = playTrack(pickTrack(current.name), volume)
        return
    end

    local duration = current.source:getDuration()
    if duration > 0 and duration - current.source:tell() <= CROSSFADE then
        beginCrossfade(current)
    end
end

return Music
