local Audio = {}

local DEFAULT_VOLUME = 1.0
local volumes = { music = DEFAULT_VOLUME, sfx = DEFAULT_VOLUME }

local tracked = { music = {}, sfx = {} }
local nextId = { music = 0, sfx = 0 }

--- fails loudly on a typo'd category rather than silently tracking nothing
---@param category "music"|"sfx"
local function assertCategory(category)
    assert(tracked[category], "Audio: unknown category '" .. tostring(category) .. "'")
end

--- drop sources that finished playing so tracked doesn't grow forever
---@param category "music"|"sfx"
local function prune(category)
    for id, entry in pairs(tracked[category]) do
        if not entry.source:isPlaying() then
            tracked[category][id] = nil
        end
    end
end

--- sets a category's volume and retunes everything currently playing in it,
-- each keeping its own per-source gain
---@param category "music"|"sfx"
---@param value number # 0..1
function Audio.setVolume(category, value)
    assertCategory(category)
    volumes[category] = value
    for _, entry in pairs(tracked[category]) do
        entry.source:setVolume(value * entry.gain)
    end
end

---@param category "music"|"sfx"
---@return number # 0..1
function Audio.getVolume(category)
    assertCategory(category)
    return volumes[category]
end

--- plays a source under a category's volume and tracks it, so a later
-- setVolume reaches it
---@param category "music"|"sfx"
---@param source any # a love.Source; nil is a no-op, so a failed preload doesn't crash a call site
---@param opts? table # { volume?: number, loop?: boolean }; volume is a per-source gain on top of the category's
---@return any # a love.Source, or nil
function Audio.play(category, source, opts)
    assertCategory(category)
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

--- stops one source, or the whole category when `source` is omitted
---@param category "music"|"sfx"
---@param source? any # a love.Source
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

--- silences every category
function Audio.stopAll()
    for category in pairs(tracked) do
        Audio.stop(category)
    end
end

return Audio
