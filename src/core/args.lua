--- Command line lookups.

local Args = {}

---@param args string[]
---@param flag string
---@return boolean
function Args.has(args, flag)
    for _, value in ipairs(args or {}) do
        if value == flag then return true end
    end
    return false
end

--- the value right after `flag`, if present
---@param args string[]
---@param flag string
---@return string|nil
function Args.value(args, flag)
    for i, value in ipairs(args or {}) do
        if value == flag then return args[i + 1] end
    end
end

return Args
