--- Per-category volume for everything playing ("music", "sfx").

local Mixer = {}

local volumes = { music = 1, sfx = 1 }
local playing = { music = {}, sfx = {} } -- source -> its own gain

---@param category string
local function check(category)
    assert(playing[category], "Mixer: unknown category '" .. tostring(category) .. "'")
end

---@param category string
local function prune(category)
    for source in pairs(playing[category]) do
        if not source:isPlaying() then playing[category][source] = nil end
    end
end

--- retunes everything already playing in the category
---@param category "music"|"sfx"
---@param value number # 0..1
function Mixer.setVolume(category, value)
    check(category)
    volumes[category] = value
    for source, gain in pairs(playing[category]) do
        source:setVolume(value * gain)
    end
end

---@param category "music"|"sfx"
---@return number
function Mixer.getVolume(category)
    check(category)
    return volumes[category]
end

--- nil sources are ignored, so a failed preload never crashes
---@param category "music"|"sfx"
---@param source any # a love.Source
---@param opts? table # { volume?: number, loop?: boolean }
---@return any # the source
function Mixer.play(category, source, opts)
    check(category)
    if not source then return nil end
    opts = opts or {}
    prune(category)

    local gain = opts.volume or 1
    source:setVolume(volumes[category] * gain)
    source:setLooping(opts.loop or false)
    source:play()
    playing[category][source] = gain
    return source
end

--- one source, or the whole category
---@param category "music"|"sfx"
---@param source? any
function Mixer.stop(category, source)
    check(category)
    if source then
        source:stop()
        playing[category][source] = nil
        return
    end
    for each in pairs(playing[category]) do each:stop() end
    playing[category] = {}
end

function Mixer.stopAll()
    for category in pairs(playing) do Mixer.stop(category) end
end

return Mixer
