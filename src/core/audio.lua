-- src/core/audio.lua
-- Independent audio "channels" (music/sfx), since LÖVE itself has no bus
-- concept — love.audio.setVolume() is a single global multiplier over every
-- Source. Category volume is implemented by scaling each Source's own volume
-- instead; the master slider keeps using love.audio.setVolume (see
-- Settings.apply), which multiplies on top of a Source's own volume, so
-- master * category falls out for free with no double-tracking.
--
--   Audio.play("music", source, { loop = true }) -- sets volume, plays, tracks
--   Audio.setVolume("music", 0.5)                 -- live-retunes tracked sources
--   Audio.getVolume("sfx")
--   Audio.stop("music")                           -- stops the whole channel
--   Audio.stop("sfx", source)                     -- stops just that source
--   Audio.stopAll()

local Audio = {}

local DEFAULT_VOLUME = 1.0
local volumes = { music = DEFAULT_VOLUME, sfx = DEFAULT_VOLUME }

-- Sources currently playing per category, so a live slider drag can retune
-- them immediately (matters for looping music; one-shot sfx will simply have
-- already finished by the time anyone notices). Keyed by an incrementing id
-- rather than array position: entries are cleared to nil as sources finish
-- (see prune below), and a plain sequence with holes has undefined `#`/insert
-- behavior in Lua once that happens.
--
-- Each entry is { source, gain }: `gain` is the per-play multiplier from
-- Audio.play's opts.volume, kept so a later setVolume can retune the source
-- without flattening it back to the plain channel volume. That's what lets a
-- deliberately quiet sound (the focus-move blip, which fires on every arrow
-- press) stay quiet relative to the rest of its channel.
local tracked = { music = {}, sfx = {} }
local nextId = { music = 0, sfx = 0 }

local function assertCategory(category)
    assert(tracked[category], "Audio: unknown category '" .. tostring(category) .. "'")
end

-- Drops sources that have finished playing so the tracked table doesn't grow
-- without bound over a long session.
local function prune(category)
    for id, entry in pairs(tracked[category]) do
        if not entry.source:isPlaying() then
            tracked[category][id] = nil
        end
    end
end

-- Re-applies to every tracked source, so a live options drag retunes music
-- that's already playing instead of waiting for the next track.
function Audio.setVolume(category, value)
    assertCategory(category)
    volumes[category] = value
    for _, entry in pairs(tracked[category]) do
        entry.source:setVolume(value * entry.gain)
    end
end

function Audio.getVolume(category)
    assertCategory(category)
    return volumes[category]
end

-- Plays `source` at the category's current volume and tracks it so future
-- Audio.setVolume calls retune it live. opts.loop sets looping (default off);
-- opts.volume is a 0..1 multiplier on top of the channel volume, for sounds
-- that should sit below the rest of their category.
function Audio.play(category, source, opts)
    assertCategory(category)
    -- Preloading is best-effort (see src/utils/audios.lua): a clip that failed
    -- to load arrives here as nil, and a missing sound effect shouldn't take
    -- the game down mid-click. The failure was already logged at boot.
    if not source then return nil end
    opts = opts or {}
    prune(category)

    local gain = opts.volume or 1
    source:setVolume(volumes[category] * gain)
    source:setLooping(opts.loop or false)
    source:play()

    nextId[category] = nextId[category] + 1
    tracked[category][nextId[category]] = { source = source, gain = gain }
    return source
end

-- With `source`, stops only that one; without, stops the whole category, so a
-- caller that never kept the Source Audio.play returned can still kill it.
--
-- LÖVE's Source:stop rewinds, so playing a stopped source again restarts the
-- track rather than resuming it.
function Audio.stop(category, source)
    assertCategory(category)

    -- Clearing keys during a pairs() traversal is fine in Lua; only *adding*
    -- keys mid-traversal is undefined.
    if source then
        source:stop()
        for id, entry in pairs(tracked[category]) do
            if entry.source == source then
                tracked[category][id] = nil
            end
        end
        return
    end

    for id, entry in pairs(tracked[category]) do
        entry.source:stop()
        tracked[category][id] = nil
    end
end

function Audio.stopAll()
    for category in pairs(tracked) do
        Audio.stop(category)
    end
end

return Audio
