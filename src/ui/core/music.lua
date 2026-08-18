-- Background music for the menu: picks a random track, plays it through, and
-- crossfades into another random track (never a repeat) as it nears its end
-- -- forever, so the menu never falls silent or cuts hard between songs.
--
--   Music.start()      -- once, when the music should begin (MainMenu:enter())
--   Music.update(dt)   -- every frame, globally (main.lua), not just while
--                         the menu is active, so a crossfade due while on
--                         Options still happens on schedule
--   Music.stop()       -- forgets what was playing; pair with Audio.stop/stopAll
--                         to actually silence it
--
-- Tracks are preloaded as streams by states/loading.lua's CLIPS list and
-- handed out by name through utils/audios.lua, like every other clip.

local Audio = require "core.audio"
local Audios = require "utils.audios"
local Math = require "utils.math"

local Music = {}

local TRACKS = { "mainMenuBG", "mainMenuBG2", "mainMenuBG3" } -- names loading.lua preloads these under

-- seconds before a track ends that the next starts fading in; also the fade's
-- own length, so the incoming track reaches full volume exactly as the outgoing one would end
local CROSSFADE = 4

local FADE_IN = 1.5 -- the very first track of a session eases up too, just faster, so it doesn't pop in

local current = nil  -- { source, name }
local next_   = nil  -- { source, name, fade = 0..1 }, set once a crossfade begins
local introFade = 1  -- 0..1; only < 1 while the very first track eases in

-- never `exclude` (the one playing) as long as there's another to pick, or
-- "the next track" sometimes reads as the same one stuttering back to the start
local function pickTrack(exclude)
    if #TRACKS <= 1 then return TRACKS[1] end
    local name
    repeat
        name = TRACKS[Math.randInt(1, #TRACKS)]
    until name ~= exclude
    return name
end

-- starts `name` (not looping -- update() decides what plays next); nil if
-- the clip never loaded (best-effort, see Audios.preload)
local function playTrack(name)
    local source = Audios.get(name)
    if not source then return nil end
    Audio.play("music", source, { loop = false })
    return { source = source, name = name }
end

-- begins the menu music, or resumes it if a track finished while nothing
-- polled update() (player was on another screen). No-op while something's
-- already playing, so re-entering the menu doesn't restart from zero.
function Music.start()
    if current and current.source:isPlaying() then return end

    current = playTrack(pickTrack(current and current.name))
    if current then
        introFade = 0
        -- Audio.play just set full channel volume; silence it before
        -- update()'s fade-in runs, or there's a one-frame blip at full volume
        current.source:setVolume(0)
    end
end

-- forgets what was playing without stopping the Source -- for when something
-- else already silenced it and Music just needs to know, so the next start() picks a fresh track
function Music.stop()
    current, next_ = nil, nil
end

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

        -- swap once the incoming track fully takes over or the outgoing one
        -- actually stopped, whichever comes first (getDuration can be a hair
        -- optimistic, which would otherwise leave `current` pointing at a dead Source)
        if next_.fade >= 1 or not current.source:isPlaying() then
            Audio.stop("music", current.source)
            current, next_ = next_, nil
        end
        return
    end

    current.source:setVolume(volume * introFade)

    if not current.source:isPlaying() then
        -- ended before the crossfade window caught it; jump to a new track rather than going silent
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
