-- proprietary json encoder/decoder
--
-- json.decode(text, { null = json.null, maxDepth = 512 })
-- json.encode(value, { indent = 2, sortKeys = true, emptyTable = "array" })
-- Both raise "json.encode: ..." / "json.decode: ..." on failure; pcall them
-- when the input isn't trusted.

local json = {}

local byte, char, sub, find, match, format, rep =
    string.byte, string.char, string.sub, string.find, string.match, string.format, string.rep
local concat, sort = table.concat, table.sort
local floor, huge = math.floor, math.huge

local escapes = {
    ['"'] = '"', ['\\'] = '\\', ['/'] = '/',
    b = '\b', f = '\f', n = '\n', r = '\r', t = '\t',
}

-- decode turns null into nil unless given { null = json.null }, which keeps
-- array positions and object keys that a nil would erase
json.null = setmetatable({}, {
    __tostring = function() return "null" end,
    __newindex = function() error("json.null is read-only", 2) end,
})

-- an empty table has no keys to tell [] from {}, so the kind is remembered
-- here: set by json.array/json.object, and by decode for empty containers so
-- they re-encode as they were read
local kinds = setmetatable({}, { __mode = "k" })

--- Marks t (or a new table) to encode as an array; holes become null.
function json.array(t)
    t = t or {}
    kinds[t] = "array"
    return t
end

--- Marks t (or a new table) to encode as an object; number keys become strings.
function json.object(t)
    t = t or {}
    kinds[t] = "object"
    return t
end

local Failure = {}

local function fail(message)
    error(setmetatable({ message = message }, Failure), 0)
end

local function rethrow(err, prefix)
    if getmetatable(err) == Failure then
        error(prefix .. err.message, 3)
    end
    error(err, 0)
end

-- Encoding

local escaped = {
    ['"'] = '\\"', ['\\'] = '\\\\',
    ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
}

local function escapeChar(c)
    return escaped[c] or format("\\u%04x", byte(c))
end

local function encodeString(s)
    return '"' .. s:gsub('[%z\1-\31"\\\127]', escapeChar) .. '"'
end

local function pathString(st)
    local parts = { "$" }
    for i, key in ipairs(st.path) do
        if type(key) == "number" then
            parts[i + 1] = "[" .. key .. "]"
        elseif match(key, "^[%a_][%w_]*$") then
            parts[i + 1] = "." .. key
        else
            parts[i + 1] = "[" .. encodeString(key) .. "]"
        end
    end
    return concat(parts)
end

local function encodeFail(st, message, ...)
    fail(format(message, ...) .. " at " .. pathString(st))
end

local function push(st, piece)
    st.n = st.n + 1
    st.buf[st.n] = piece
end

local function newline(st, depth)
    if st.indent then
        push(st, "\n" .. rep(st.indent, depth))
    end
end

local function numberToString(st, n)
    if n ~= n or n == huge or n == -huge then
        encodeFail(st, "cannot encode %s", tostring(n))
    end
    if floor(n) == n and n >= -2^53 and n <= 2^53 then
        return format("%d", n)
    end
    -- shortest form that reads back to the same double
    local s = format("%.14g", n)
    if tonumber(s) ~= n then
        s = format("%.17g", n)
    end
    return s
end

---@return "array"|"object" kind
---@return integer? length
local function classify(st, t)
    local count, maxIndex, allIndices = 0, 0, true
    for k in pairs(t) do
        count = count + 1
        if type(k) == "number" and k >= 1 and floor(k) == k then
            if k > maxIndex then maxIndex = k end
        else
            allIndices = false
        end
    end

    local tagged = kinds[t]
    if tagged == "object" then
        return "object"
    elseif tagged == "array" then
        if not allIndices then
            encodeFail(st, "table marked json.array has non-index keys")
        end
        return "array", maxIndex
    elseif count == 0 then
        return st.emptyTable, 0
    elseif allIndices then
        if maxIndex ~= count then
            encodeFail(st, "sparse array (%d entries, highest index %d); fill the holes "
                .. "with json.null, or mark it json.array or json.object", count, maxIndex)
        end
        return "array", count
    end
    return "object"
end

local encodeValue

local function encodeArray(st, t, length, depth)
    if length == 0 then
        push(st, "[]")
        return
    end
    push(st, "[")
    local path = st.path
    for i = 1, length do
        if i > 1 then push(st, ",") end
        newline(st, depth + 1)
        path[#path + 1] = i
        encodeValue(st, t[i], depth + 1)
        path[#path] = nil
    end
    newline(st, depth)
    push(st, "]")
end

local function encodeObject(st, t, depth)
    local names, lookup = {}, {}
    local stringifyNumbers = kinds[t] == "object"
    for k in pairs(t) do
        local name
        local keyType = type(k)
        if keyType == "string" then
            name = k
        elseif keyType == "number" and stringifyNumbers then
            name = numberToString(st, k)
        elseif keyType == "number" then
            encodeFail(st, "number key %s in a table with string keys; mark it json.object "
                .. "to write number keys as strings", tostring(k))
        else
            encodeFail(st, "cannot use a %s as an object key", keyType)
        end
        if lookup[name] ~= nil then
            encodeFail(st, "duplicate key %s", encodeString(name))
        end
        names[#names + 1] = name
        lookup[name] = k
    end

    if #names == 0 then
        push(st, "{}")
        return
    end
    if st.sortKeys then sort(names) end

    push(st, "{")
    local path = st.path
    for i, name in ipairs(names) do
        if i > 1 then push(st, ",") end
        newline(st, depth + 1)
        push(st, encodeString(name))
        push(st, st.colon)
        path[#path + 1] = name
        encodeValue(st, t[lookup[name]], depth + 1)
        path[#path] = nil
    end
    newline(st, depth)
    push(st, "}")
end

-- raw skips __tojson, so a hook that returns its own table doesn't recurse forever
function encodeValue(st, v, depth, raw)
    local t = type(v)
    if t == "string" then
        push(st, encodeString(v))
    elseif t == "number" then
        push(st, numberToString(st, v))
    elseif t == "boolean" then
        push(st, v and "true" or "false")
    elseif v == nil or rawequal(v, json.null) then
        push(st, "null")
    elseif t == "table" then
        local mt = getmetatable(v)
        local hook = not raw and type(mt) == "table" and mt.__tojson
        if hook then
            return encodeValue(st, hook(v), depth, true)
        end
        if st.seen[v] then
            encodeFail(st, "circular reference")
        end
        st.seen[v] = true
        local kind, length = classify(st, v)
        if kind == "array" then
            encodeArray(st, v, length, depth)
        else
            encodeObject(st, v, depth)
        end
        st.seen[v] = nil
    else
        encodeFail(st, "cannot encode a %s", t)
    end
end

--- Serializes a Lua value to JSON text.
--- A table encodes as an array when its keys are exactly 1..n, as an object
--- when they're all strings; a metatable's __tojson(t) can return a plain
--- value to encode in its place.
---@param value any
---@param opts? { indent?: integer|string, sortKeys?: boolean, emptyTable?: "array"|"object" }
---@return string
function json.encode(value, opts)
    opts = opts or {}
    local indent = opts.indent
    if type(indent) == "number" then
        indent = rep(" ", indent)
    end
    local emptyTable = opts.emptyTable or "array"
    if emptyTable ~= "array" and emptyTable ~= "object" then
        error("json.encode: emptyTable must be \"array\" or \"object\"", 2)
    end

    local st = {
        buf = {}, n = 0, seen = {}, path = {},
        indent = indent or nil,
        colon = indent and ": " or ":",
        sortKeys = opts.sortKeys,
        emptyTable = emptyTable,
    }
    local ok, err = pcall(encodeValue, st, value, 0)
    if not ok then rethrow(err, "json.encode: ") end
    return concat(st.buf, "", 1, st.n)
end

-- Decoding

-- per-call state; safe as upvalues because decoding never calls user code
local text, nullValue, maxDepth

local function decodeFail(pos, message, ...)
    local line, lineStart = 1, 1
    while true do
        local nl = find(text, "\n", lineStart, true)
        if not nl or nl >= pos then break end
        line, lineStart = line + 1, nl + 1
    end
    fail(format(message, ...) .. format(" at line %d, column %d", line, pos - lineStart + 1))
end

local function skipWhitespace(pos)
    return find(text, "[^ \t\r\n]", pos) or #text + 1
end

local function utf8Encode(cp)
    if cp < 0x80 then
        return char(cp)
    elseif cp < 0x800 then
        return char(0xC0 + floor(cp / 0x40),
                    0x80 + cp % 0x40)
    elseif cp < 0x10000 then
        return char(0xE0 + floor(cp / 0x1000),
                    0x80 + floor(cp / 0x40) % 0x40,
                    0x80 + cp % 0x40)
    end
    return char(0xF0 + floor(cp / 0x40000),
                0x80 + floor(cp / 0x1000) % 0x40,
                0x80 + floor(cp / 0x40) % 0x40,
                0x80 + cp % 0x40)
end

-- pos is the backslash of a \uXXXX; joins surrogate pairs, and a lone
-- surrogate becomes U+FFFD rather than invalid UTF-8
local function parseUnicodeEscape(pos)
    local hex = match(text, "^%x%x%x%x", pos + 2)
    if not hex then
        decodeFail(pos, "invalid \\u escape")
    end
    local cp = tonumber(hex, 16)
    local nextPos = pos + 6
    if cp >= 0xD800 and cp <= 0xDBFF then
        local low = match(text, "^\\u(%x%x%x%x)", nextPos)
        low = low and tonumber(low, 16)
        if low and low >= 0xDC00 and low <= 0xDFFF then
            cp = 0x10000 + (cp - 0xD800) * 0x400 + (low - 0xDC00)
            nextPos = nextPos + 6
        else
            cp = 0xFFFD
        end
    elseif cp >= 0xDC00 and cp <= 0xDFFF then
        cp = 0xFFFD
    end
    return utf8Encode(cp), nextPos
end

local function parseString(pos)
    local parts, n = nil, 0
    local i = pos + 1
    while true do
        local j = find(text, '[%z\1-\31"\\]', i)
        if not j then
            decodeFail(pos, "unterminated string")
        end
        local c = byte(text, j)
        if c == 34 then
            if not parts then
                return sub(text, i, j - 1), j + 1
            end
            parts[n + 1] = sub(text, i, j - 1)
            return concat(parts), j + 1
        elseif c == 92 then
            parts = parts or {}
            n = n + 1
            parts[n] = sub(text, i, j - 1)
            local e = sub(text, j + 1, j + 1)
            n = n + 1
            if e == "u" then
                parts[n], i = parseUnicodeEscape(j)
            elseif escapes[e] then
                parts[n], i = escapes[e], j + 2
            else
                decodeFail(j, "invalid escape '\\%s'", e)
            end
        else
            decodeFail(j, "unescaped control character in string")
        end
    end
end

local function isDigit(c)
    return c and c >= 48 and c <= 57
end

local function parseNumber(pos)
    local i = pos
    if byte(text, i) == 45 then i = i + 1 end
    local c = byte(text, i)
    if c == 48 then
        i = i + 1
    elseif isDigit(c) then
        i = select(2, find(text, "^%d+", i)) + 1
    else
        decodeFail(pos, "invalid number")
    end
    if byte(text, i) == 46 then
        local _, e = find(text, "^%d+", i + 1)
        if not e then decodeFail(i, "expected a digit after '.'") end
        i = e + 1
    end
    c = byte(text, i)
    if c == 101 or c == 69 then
        local _, e = find(text, "^[-+]?%d+", i + 1)
        if not e then decodeFail(i, "invalid exponent") end
        i = e + 1
    end
    return tonumber(sub(text, pos, i - 1)), i
end

local parseValue

local function parseArray(pos, depth)
    local arr, n = {}, 0
    pos = skipWhitespace(pos + 1)
    if byte(text, pos) == 93 then
        kinds[arr] = "array"
        return arr, pos + 1
    end
    while true do
        local value
        value, pos = parseValue(pos, depth)
        n = n + 1
        arr[n] = value
        if value == nil then
            -- a null left a hole; re-encode it as one instead of rejecting a sparse array
            kinds[arr] = "array"
        end
        pos = skipWhitespace(pos)
        local c = byte(text, pos)
        if c == 93 then
            return arr, pos + 1
        elseif c ~= 44 then
            decodeFail(pos, "expected ',' or ']'")
        end
        pos = pos + 1
    end
end

local function parseObject(pos, depth)
    local obj = {}
    pos = skipWhitespace(pos + 1)
    if byte(text, pos) == 125 then
        kinds[obj] = "object"
        return obj, pos + 1
    end
    while true do
        if byte(text, pos) ~= 34 then
            decodeFail(pos, "expected a string key")
        end
        local key, value
        key, pos = parseString(pos)
        pos = skipWhitespace(pos)
        if byte(text, pos) ~= 58 then
            decodeFail(pos, "expected ':'")
        end
        value, pos = parseValue(pos + 1, depth)
        obj[key] = value
        pos = skipWhitespace(pos)
        local c = byte(text, pos)
        if c == 125 then
            return obj, pos + 1
        elseif c ~= 44 then
            decodeFail(pos, "expected ',' or '}'")
        end
        pos = skipWhitespace(pos + 1)
    end
end

local literals = { t = { "true", true }, f = { "false", false }, n = { "null" } }

function parseValue(pos, depth)
    pos = skipWhitespace(pos)
    local c = byte(text, pos)
    if c == 123 or c == 91 then
        if depth >= maxDepth then
            decodeFail(pos, "nested deeper than %d levels", maxDepth)
        end
        if c == 123 then
            return parseObject(pos, depth + 1)
        end
        return parseArray(pos, depth + 1)
    elseif c == 34 then
        return parseString(pos)
    elseif c == 45 or isDigit(c) then
        return parseNumber(pos)
    elseif c then
        local literal = literals[char(c)]
        if literal and sub(text, pos, pos + #literal[1] - 1) == literal[1] then
            local value = literal[2]
            if value == nil then value = nullValue end
            return value, pos + #literal[1]
        end
        decodeFail(pos, "unexpected character '%s'", char(c))
    end
    decodeFail(pos, "unexpected end of input")
end

local function decodeDocument()
    local start = sub(text, 1, 3) == "\239\187\191" and 4 or 1
    local value, pos = parseValue(start, 0)
    pos = skipWhitespace(pos)
    if pos <= #text then
        decodeFail(pos, "unexpected trailing '%s'", sub(text, pos, pos))
    end
    return value
end

--- Parses JSON text into Lua values. Objects become string-keyed tables,
--- arrays 1-based sequences, null becomes opts.null (nil by default).
---@param str string
---@param opts? { null?: any, maxDepth?: integer }
---@return any
function json.decode(str, opts)
    if type(str) ~= "string" then
        error("json.decode: expected a string, got " .. type(str), 2)
    end
    text = str
    nullValue = opts and opts.null
    maxDepth = opts and opts.maxDepth or 512
    local ok, result = pcall(decodeDocument)
    text, nullValue = nil, nil
    if not ok then rethrow(result, "json.decode: ") end
    return result
end

return json
