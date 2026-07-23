-- lib/audio.lua
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

local Audio = {}

local DEFAULT_VOLUME = 1.0
local volumes = { music = DEFAULT_VOLUME, sfx = DEFAULT_VOLUME }

-- Sources currently playing per category, so a live slider drag can retune
-- them immediately (matters for looping music; one-shot sfx will simply have
-- already finished by the time anyone notices). Keyed by an incrementing id
-- rather than array position: entries are cleared to nil as sources finish
-- (see prune below), and a plain sequence with holes has undefined `#`/insert
-- behavior in Lua once that happens.
local tracked = { music = {}, sfx = {} }
local nextId = { music = 0, sfx = 0 }

local function assertCategory(category)
    assert(tracked[category], "Audio: unknown category '" .. tostring(category) .. "'")
end

-- Drops sources that have finished playing so the tracked table doesn't grow
-- without bound over a long session.
local function prune(category)
    for id, source in pairs(tracked[category]) do
        if not source:isPlaying() then
            tracked[category][id] = nil
        end
    end
end

-- Sets a category's volume and immediately re-applies it to every source
-- currently tracked in that category, so a live options-menu drag retunes
-- music that's already playing instead of waiting for the next track.
function Audio.setVolume(category, value)
    assertCategory(category)
    volumes[category] = value
    for _, source in pairs(tracked[category]) do
        source:setVolume(value)
    end
end

function Audio.getVolume(category)
    assertCategory(category)
    return volumes[category]
end

-- Plays `source` at the category's current volume and tracks it so future
-- Audio.setVolume calls retune it live. opts.loop sets looping (default off).
function Audio.play(category, source, opts)
    assertCategory(category)
    opts = opts or {}
    prune(category)

    source:setVolume(volumes[category])
    source:setLooping(opts.loop or false)
    source:play()

    nextId[category] = nextId[category] + 1
    tracked[category][nextId[category]] = source
    return source
end

return Audio
