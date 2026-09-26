--- Background music: picks a random track from the active playlist, plays it
-- through, and crossfades into another (never a repeat) as it nears its end
-- -- forever, so a screen never falls silent or cuts hard between songs.
--
--   Music.start("menu")  -- on entering a screen; a no-op if that playlist is
--                           already playing, a crossfade if another one is
--   Music.update(dt)     -- every frame, globally (main.lua), not just while
--                           a given screen is active, so a crossfade due while
--                           on Options still happens on schedule
--   Music.stop()         -- forgets what was playing; pair with Audio.stop/stopAll
--                           to actually silence it
--
-- Tracks are preloaded as streams by states/loading.lua's CLIPS list and
-- handed out by name through utils/audios.lua, like every other clip.

local Audio = require "core.audio"
local Audios = require "utils.audios"
local Math = require "utils.math"

local Music = {}

local PLAYLISTS = {
    menu = { "mainMenuBG", "mainMenuBG2", "mainMenuBG3" },
    game = { "forest", "StarryNight", "Snowfall" },
}

local CROSSFADE = 4

local FADE_IN = 1.5 -- the very first track of a session eases up too, just faster, so it doesn't pop in

local current = nil  -- { source, name }
local next_   = nil  -- { source, name, fade = 0..1 }, set once a crossfade begins
local introFade = 1  -- 0..1; only < 1 while the very first track eases in
local playlist = "menu"

--- never `exclude` (the one playing) as long as there's another to pick, or
-- "the next track" sometimes reads as the same one stuttering back to the start
---@param exclude string|nil # the track currently playing
---@return string name
local function pickTrack(exclude)
    local tracks = PLAYLISTS[playlist]
    if #tracks <= 1 then return tracks[1] end
    local name
    repeat
        name = tracks[Math.randInt(1, #tracks)]
    until name ~= exclude
    return name
end

--- starts `name` (not looping -- update() decides what plays next); nil if
-- the clip never loaded (best-effort, see Audios.preload)
---@param name string
---@return table|nil # { source: love.Source, name: string }
local function playTrack(name)
    local source = Audios.get(name)
    if not source then return nil end
    Audio.play("music", source, { loop = false })
    return { source = source, name = name }
end

--- begins `kind`'s playlist, or resumes it if a track finished while nothing
-- polled update(). No-op while that playlist is already playing, so
-- re-entering a screen doesn't restart it from zero; crossfades out of
-- whatever else is playing.
---@param kind "menu"|"game"
function Music.start(kind)
    assert(PLAYLISTS[kind], "Music.start: no playlist named '" .. tostring(kind) .. "'")
    local playing = current and current.source:isPlaying()
    if playing and kind == playlist then return end
    playlist = kind

    if not playing then
        current = playTrack(pickTrack(current and current.name))
        if current then
            introFade = 0
            current.source:setVolume(0)
        end
        return
    end

    if next_ then
        Audio.stop("music", current.source)
        current = next_
    end
    next_ = playTrack(pickTrack(current.name))
    if next_ then
        next_.fade = 0
        next_.source:setVolume(0)
    end
end

--- forgets what was playing without stopping the Source -- for when something
-- else already silenced it and Music just needs to know, so the next start() picks a fresh track
function Music.stop()
    current, next_ = nil, nil
end

--- drives the whole cycle: eases the first track in, runs a crossfade once
-- one is due, and starts the next track when one ends outright
---@param dt number
function Music.update(dt)
    if not current then return end
    local volume = Audio.getVolume("music")

    if introFade < 1 then
        introFade = math.min(1, introFade + dt / FADE_IN)
    end

    if next_ then
        next_.fade = math.min(1, next_.fade + dt / CROSSFADE)
        next_.source:setVolume(volume * next_.fade)
        current.source:setVolume(volume * (1 - next_.fade) * introFade)

        if next_.fade >= 1 or not current.source:isPlaying() then
            Audio.stop("music", current.source)
            current, next_ = next_, nil
        end
        return
    end

    current.source:setVolume(volume * introFade)

    if not current.source:isPlaying() then
        current = playTrack(pickTrack(current.name))
        introFade = 1
        return
    end

    local duration = current.source:getDuration()
    if duration <= 0 then return end -- LÖVE couldn't determine it; the isPlaying() check above covers it instead

    if duration - current.source:tell() <= CROSSFADE then
        next_ = playTrack(pickTrack(current.name))
        if next_ then
            next_.fade = 0
            next_.source:setVolume(0) -- see start(), same reason
        end
    end
end

return Music
