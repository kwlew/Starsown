-- src/ui/core/music.lua
-- Background music for the menu: picks a random track, plays it through, and
-- crossfades smoothly into another random track (never a repeat of the one
-- that just played) as it nears its end -- forever, so the menu never falls
-- silent or cuts hard between songs.
--
--   Music.start()      -- once, when the music should begin (MainMenu:enter())
--   Music.update(dt)   -- every frame, globally (main.lua) -- not just while
--                         the menu is the active screen, so a crossfade due
--                         while the player is on Options still happens on
--                         schedule instead of leaving the menu silent when
--                         they come back
--   Music.stop()       -- forgets what was playing; pair with Audio.stop or
--                         Audio.stopAll(), which is what actually silences it
--
-- Tracks are preloaded as streams by states/loading.lua's CLIPS list and
-- handed out by name through utils/audios.lua, the same as every other clip.

local Audio = require "core.audio"
local Audios = require "utils.audios"
local Math = require "utils.math"

local Music = {}

-- Names loading.lua preloads these under (see the CLIPS list there).
local TRACKS = { "mainMenuBG", "mainMenuBG2", "mainMenuBG3" }

-- Seconds before a track ends that the next one starts fading in underneath
-- it. The same span doubles as the fade's own length: the incoming track
-- needs exactly this long to reach full volume by the moment the outgoing
-- one would otherwise have gone silent.
local CROSSFADE = 4

-- The very first track of a session eases up from silence too, just faster --
-- an instant needle-drop to full volume the moment the menu appears reads as
-- a pop, not a start.
local FADE_IN = 1.5

local current = nil  -- { source, name }
local next_   = nil  -- { source, name, fade = 0..1 }, set once a crossfade begins
local introFade = 1  -- 0..1; only < 1 while the very first track eases in

-- A random track name, never `exclude` (the one currently playing) as long as
-- there's another to pick -- otherwise "the next track" would sometimes just
-- be the same one starting over, which reads as a stutter, not a change.
local function pickTrack(exclude)
    if #TRACKS <= 1 then return TRACKS[1] end
    local name
    repeat
        name = TRACKS[Math.randInt(1, #TRACKS)]
    until name ~= exclude
    return name
end

-- Starts `name` playing (not looping -- update() decides what plays next) and
-- returns the {source, name} pair Music tracks it under, or nil if the clip
-- never loaded (best-effort, like every other clip -- see Audios.preload).
local function playTrack(name)
    local source = Audios.get(name)
    if not source then return nil end
    Audio.play("music", source, { loop = false })
    return { source = source, name = name }
end

-- Begins the menu music, or resumes it if a track finished while nothing was
-- polling update() -- the player was on another screen when it ended, so
-- `current` is still set but its Source has already gone quiet on its own.
-- A no-op while something is already audibly playing, so re-entering the menu
-- from Options doesn't restart the track from zero.
function Music.start()
    if current and current.source:isPlaying() then return end

    current = playTrack(pickTrack(current and current.name))
    if current then
        introFade = 0
        -- Audio.play just set this to full channel volume; silence it before
        -- update()'s fade-in gets a chance to run, so there's no one-frame
        -- blip at full volume before the ease-in takes over.
        current.source:setVolume(0)
    end
end

-- Forgets what was playing. Doesn't stop the Source itself -- pair with
-- Audio.stop("music") or Audio.stopAll() for that; this is for the case where
-- something else already silenced it and Music just needs to know, so the
-- next Music.start() picks a fresh track instead of thinking one's still due.
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

        -- Swap once the incoming track has fully taken over, or the outgoing
        -- one has actually stopped -- whichever comes first. A track that
        -- ends a little earlier than getDuration() claimed would otherwise
        -- leave `current` pointing at a dead Source until the next check.
        if next_.fade >= 1 or not current.source:isPlaying() then
            Audio.stop("music", current.source)
            current, next_ = next_, nil
        end
        return
    end

    current.source:setVolume(volume * introFade)

    if not current.source:isPlaying() then
        -- Ended before the crossfade window below ever caught it -- jump
        -- straight to a new track rather than leaving the menu silent.
        current = playTrack(pickTrack(current.name))
        introFade = 1
        return
    end

    local duration = current.source:getDuration()
    if duration <= 0 then return end -- LÖVE couldn't determine it; skip ahead to the isPlaying() check above instead

    if duration - current.source:tell() <= CROSSFADE then
        next_ = playTrack(pickTrack(current.name))
        if next_ then
            next_.fade = 0
            next_.source:setVolume(0) -- see the note in start() -- same reason
        end
    end
end

return Music
