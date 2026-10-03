--- Shared objects by name, built once and reused across states.

local Assets = { store = {} }

--- stores and returns the value, for inline use
---@param name string
---@param value any
---@return any
function Assets.set(name, value)
    Assets.store[name] = value
    return value
end

---@param name string
---@return any|nil
function Assets.get(name)
    return Assets.store[name]
end

return Assets
