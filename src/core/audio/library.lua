--- Preloaded sources: get() shares, clone() copies for overlap.

local Library = {}

local cache = {}

---@param path string
---@param name string
---@param sourceType? "static"|"stream"
function Library.preload(path, name, sourceType)
    local ok, source = pcall(love.audio.newSource, path, sourceType or "static")
    if not ok then
        print(("[audio] failed to preload '%s' from %s: %s"):format(name, path, tostring(source)))
        return nil, source
    end
    cache[name] = source
    return source
end

--- the shared source; right for music
---@param name string
---@return any|nil
function Library.get(name)
    return cache[name]
end

--- a fresh copy; right for overlapping sfx
---@param name string
---@return any|nil
function Library.clone(name)
    local source = cache[name]
    return source and source:clone()
end

return Library
