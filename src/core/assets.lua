local Assets = { store = {} }

--- files a loaded asset under a name and hands it straight back, so a load
-- site can store and use it in one expression
---@param name string
---@param value any
---@return any value
function Assets.set(name, value)
    Assets.store[name] = value
    return value
end

---@param name string
---@return any|nil # nil if nothing was stored under that name
function Assets.get(name)
    return Assets.store[name]
end

return Assets
