-- Per-category (music/sfx) volume, since love.audio.setVolume() is one global
-- multiplier over every Source. Category volume scales each Source directly;
-- the master slider still goes through love.audio.setVolume on top (Settings.apply).
--
--   Audio.play("music", source, { loop = true })
--   Audio.setVolume("music", 0.5)
--   Audio.stop("sfx", source)
--   Audio.stopAll()

local Audio = {}

local DEFAULT_VOLUME = 1.0
local volumes = { music = DEFAULT_VOLUME, sfx = DEFAULT_VOLUME }

-- keyed by incrementing id, not array index: entries get nil'd as sources
-- finish, and a sequence with holes has undefined #/insert behavior in Lua.
-- each entry: { source, gain } -- gain is the per-play volume multiplier
local tracked = { music = {}, sfx = {} }
local nextId = { music = 0, sfx = 0 }

local function assertCategory(category)
    assert(tracked[category], "Audio: unknown category '" .. tostring(category) .. "'")
end

-- drop sources that finished playing so tracked doesn't grow forever
local function prune(category)
    for id, entry in pairs(tracked[category]) do
        if not entry.source:isPlaying() then
            tracked[category][id] = nil
        end
    end
end

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

function Audio.play(category, source, opts)
    assertCategory(category)
    -- preloading is best-effort (utils/audios.lua); a failed clip is nil here
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

-- with `source`, stops just that one; without, stops the whole category.
-- LÖVE's Source:stop() rewinds, so replaying it restarts rather than resumes.
function Audio.stop(category, source)
    assertCategory(category)

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
