-- Preloads audio files once at boot and hands them out by name, so states
-- don't pay the decode/file-open cost mid-frame or each build their own
-- copy of the same track.
--
--   Audios.preload("assets/audio/bg/ambientmain_0.ogg", "mainMenuBG", "stream")
--   Audio.play("music", Audios.get("mainMenuBG"), { loop = true })
--   Audio.play("sfx", Audios.clone("starExplosion"))
--
-- get() hands back the one shared Source -- right for music, where you want
-- a single instance to stop and retune. clone() hands back a fresh copy --
-- right for sfx, since a Source only plays one instance of itself at a
-- time, so two stars popping the same frame would swallow the second pop.

local Audios = {}

-- own table rather than fields on Audios, so a clip named "get" or "preload" can't shadow the module's functions
local cache = {}

local DEFAULT_TYPE = "static" -- "static" decodes up front (short sfx), "stream" decodes as it plays (long music)

-- returns the Source, or nil plus the error, so a bad path is visible at boot instead of a silent nil at the call site
function Audios.preload(filePath, sourceName, sourceType)
    local ok, source = pcall(love.audio.newSource, filePath, sourceType or DEFAULT_TYPE)
    if not ok then
        print(("[audios] failed to preload '%s' from %s: %s")
            :format(tostring(sourceName), tostring(filePath), tostring(source)))
        return nil, source
    end

    cache[sourceName] = source
    return source
end

function Audios.get(sourceName)
    return cache[sourceName]
end

-- a fresh, stopped copy that can play over any copy already sounding; use for overlapping sfx
function Audios.clone(sourceName)
    local source = cache[sourceName]
    if not source then return nil end
    return source:clone()
end

return Audios
