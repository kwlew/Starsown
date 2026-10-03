--- Plain Lua values to loadable Lua source.
-- Unrepresentable values (functions, userdata) become `nil`.

local LuaSerialize = {}

local INDENT = "    "
local IDENTIFIER = "^[%a_][%w_]*$"

---@param t table
---@return boolean isArray
---@return integer count
local function arrayLength(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    for i = 1, n do
        if t[i] == nil then return false, 0 end
    end
    return true, n
end

---@param key string
---@return string
local function keyLiteral(key)
    if key:match(IDENTIFIER) then return key end
    return string.format("[%q]", key)
end

---@param value any
---@param depth? integer
---@return string
function LuaSerialize.value(value, depth)
    local t = type(value)
    if t == "string" then
        return string.format("%q", value)
    elseif t == "number" then
        -- shortest form that still round-trips exactly
        local short = string.format("%.14g", value)
        if tonumber(short) == value then return short end
        return string.format("%.17g", value)
    elseif t == "boolean" then
        return tostring(value)
    elseif t == "table" then
        return LuaSerialize.table(value, depth)
    end
    return "nil"
end

--- arrays when keys are exactly 1..n, otherwise sorted string-keyed maps
---@param t table
---@param depth? integer
---@return string
function LuaSerialize.table(t, depth)
    depth = depth or 0
    local pad, padIn = INDENT:rep(depth), INDENT:rep(depth + 1)
    local lines = { "{" }

    local isArray, count = arrayLength(t)
    if isArray then
        for i = 1, count do
            lines[#lines + 1] = padIn .. LuaSerialize.value(t[i], depth + 1) .. ","
        end
    else
        local keys = {}
        for key in pairs(t) do
            if type(key) == "string" then keys[#keys + 1] = key end
        end
        table.sort(keys)
        for _, key in ipairs(keys) do
            lines[#lines + 1] = padIn .. keyLiteral(key) .. " = " .. LuaSerialize.value(t[key], depth + 1) .. ","
        end
    end

    lines[#lines + 1] = pad .. "}"
    return table.concat(lines, "\n")
end

return LuaSerialize
