--- Turns a plain Lua value into loadable Lua source, recursively -- the one
-- serializer core/settings.lua builds its file format on. A value that can't
-- be represented (a function, userdata, a table with non-string/non-array
-- keys) serializes to the literal `nil` rather than producing a file that
-- won't load back.
--
-- A table is written as an array only when its keys are exactly 1..n with no
-- gaps; anything else is written as a map, sorted by key so the file diffs
-- cleanly. There is no in-between -- represent "no value at this index" with
-- an explicit placeholder (e.g. `false`) rather than a hole, since a hole
-- makes a table stop qualifying as an array partway through.
--
--   LuaSerialize.serialize({ a = 1, b = { "x", "y" } })
--   -- '{\n    a = 1,\n    b = {\n        "x",\n        "y",\n    },\n}'

local LuaSerialize = {}

local INDENT = "    "
local IDENTIFIER = "^[%a_][%w_]*$"

--- true (plus its length) only when every key is 1..n with no gaps
---@param t table
---@return boolean
---@return integer # 0 when not an array
local function isArray(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    for i = 1, n do
        if t[i] == nil then return false, 0 end
    end
    return true, n
end

--- a bareword `key = ` reads cleaner than `["key"] = ` and matches how
-- core/settings.lua already writes its keys; anything that isn't a valid
-- Lua identifier still round-trips through the quoted form
---@param key string
---@return string
local function keyLiteral(key)
    if key:match(IDENTIFIER) then return key end
    return string.format("[%q]", key)
end

--- one value as a Lua literal; used directly by anything (like
-- core/settings.lua) that only ever writes scalars and wants the same
-- quoting rules without pulling in the array/map table format below
---@param value any
---@param depth? integer # only matters if value is itself a table
---@return string
function LuaSerialize.serializeValue(value, depth)
    local t = type(value)
    if t == "string" then
        return string.format("%q", value)
    elseif t == "number" then
        -- 14 significant digits (tostring()'s own precision) is short and
        -- clean for a value that came from a plain decimal literal (a volume
        -- slider, currency, ...) and round-trips it exactly, but not always
        -- for one with more genuine precision behind it (an XP curve's
        -- output, say) -- verify it actually comes back equal, and only pay
        -- for 17 digits (the minimum always exact for a double, per IEEE
        -- 754) when 14 wasn't enough
        local short = string.format("%.14g", value)
        if tonumber(short) == value then return short end
        return string.format("%.17g", value)
    elseif t == "boolean" then
        return tostring(value)
    elseif t == "table" then
        return LuaSerialize.serialize(value, depth)
    end
    return "nil"
end

--- a table, recursively; `depth` only controls indentation and is normally
-- left for the recursion to fill in
---@param t table
---@param depth? integer
---@return string
function LuaSerialize.serialize(t, depth)
    depth = depth or 0
    local pad, padIn = INDENT:rep(depth), INDENT:rep(depth + 1)
    local lines = { "{" }

    local array, count = isArray(t)
    if array then
        for i = 1, count do
            lines[#lines + 1] = padIn .. LuaSerialize.serializeValue(t[i], depth + 1) .. ","
        end
    else
        local keys = {}
        for key in pairs(t) do
            if type(key) == "string" then keys[#keys + 1] = key end
        end
        table.sort(keys)
        for _, key in ipairs(keys) do
            lines[#lines + 1] = padIn .. keyLiteral(key) .. " = " .. LuaSerialize.serializeValue(t[key], depth + 1) .. ","
        end
    end

    lines[#lines + 1] = pad .. "}"
    return table.concat(lines, "\n")
end

return LuaSerialize
