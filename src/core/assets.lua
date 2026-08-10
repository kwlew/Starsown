-- src/core/assets.lua
-- Tiny name -> resource cache. The loading state creates resources (fonts,
-- images, audio, settings) once and stores them here; every other state
-- fetches them by name instead of rebuilding them.

local Assets = { store = {} }

function Assets.set(name, value)
    Assets.store[name] = value
    return value
end

function Assets.get(name)
    return Assets.store[name]
end

return Assets
