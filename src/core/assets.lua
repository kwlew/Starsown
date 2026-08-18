-- name -> resource cache; loading state fills it once, everyone else reads by name

local Assets = { store = {} }

function Assets.set(name, value)
    Assets.store[name] = value
    return value
end

function Assets.get(name)
    return Assets.store[name]
end

return Assets
