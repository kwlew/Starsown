-- src/utils/audios
-- Preloads audio files once at boot and hands them out by name, so states
-- don't pay the decode/file-open cost mid-frame and don't each build their own
-- copy of the same track. Intended usage:
--
--   Audios.preload("assets/audio/bg/ambientmain_0.ogg", "mainMenuBG", "stream")
--   Audio.play("music", Audios.get("mainMenuBG"), { loop = true })
--   Audio.play("sfx", Audios.clone("starExplosion"))
--
-- get() hands back the one shared Source — right for music, where you want a
-- single instance to stop and retune. clone() hands back a fresh copy — right
-- for sfx, because a Source only plays one instance of itself at a time, so
-- two stars popping in the same frame would otherwise swallow the second pop.

local Audios = {}

-- Sources keyed by name. Deliberately its own table rather than fields on
-- Audios: a clip named "get" or "preload" would otherwise shadow the module's
-- own functions.
local cache = {}

-- LÖVE's source types: "static" decodes the whole file into memory up front
-- (short sfx), "stream" decodes as it plays (long music).
local DEFAULT_TYPE = "static"

-- Loads `filePath` and caches it under `sourceName`. Returns the Source, or
-- nil plus the error, so a bad path is visible at boot instead of turning into
-- a silent nil at the call site.
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

-- The shared Source for `sourceName`, or nil if it never loaded.
function Audios.get(sourceName)
    return cache[sourceName]
end

-- A fresh, stopped copy of `sourceName` that can play over the top of any copy
-- already sounding. Use for overlapping sfx. nil if it never loaded.
function Audios.clone(sourceName)
    local source = cache[sourceName]
    if not source then return nil end
    return source:clone()
end

return Audios
