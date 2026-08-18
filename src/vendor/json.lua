-- Minimal, self-contained JSON decoder (decode only -- locale files are
-- read-only). Recursive-descent: objects, arrays, strings with the full
-- escape set including \uXXXX, numbers, true/false/null. Raises on
-- malformed input with the byte position, so callers can pcall and fall
-- back gracefully (see core/i18n.lua).

local Json = {}

local escapes = {
    ['"'] = '"', ['\\'] = '\\', ['/'] = '/',
    b = '\b', f = '\f', n = '\n', r = '\r', t = '\t',
}

local function skipWhitespace(str, i)
    local _, j = str:find("^[ \t\r\n]*", i)
    return j + 1
end

-- encodes a Unicode code point as UTF-8 (LÖVE renders UTF-8 strings directly)
local function utf8Encode(cp)
    if cp < 0x80 then
        return string.char(cp)
    elseif cp < 0x800 then
        return string.char(0xC0 + math.floor(cp / 0x40),
                           0x80 + cp % 0x40)
    elseif cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 0x1000),
                           0x80 + math.floor(cp / 0x40) % 0x40,
                           0x80 + cp % 0x40)
    else
        return string.char(0xF0 + math.floor(cp / 0x40000),
                           0x80 + math.floor(cp / 0x1000) % 0x40,
                           0x80 + math.floor(cp / 0x40) % 0x40,
                           0x80 + cp % 0x40)
    end
end

local parseValue -- forward declaration (values nest recursively)

local function parseString(str, i)
    -- i points at the opening quote
    local out = {}
    local j = i + 1
    while j <= #str do
        local c = str:sub(j, j)
        if c == '"' then
            return table.concat(out), j + 1
        elseif c == '\\' then
            local esc = str:sub(j + 1, j + 1)
            if esc == 'u' then
                local hex = str:sub(j + 2, j + 5)
                local cp = tonumber(hex, 16)
                if not cp or #hex < 4 then
                    error(("json: bad \\u escape at %d"):format(j))
                end
                -- combine a UTF-16 surrogate pair if one follows
                if cp >= 0xD800 and cp <= 0xDBFF and str:sub(j + 6, j + 7) == "\\u" then
                    local lo = tonumber(str:sub(j + 8, j + 11), 16)
                    if lo and lo >= 0xDC00 and lo <= 0xDFFF then
                        cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
                        j = j + 6
                    end
                end
                out[#out + 1] = utf8Encode(cp)
                j = j + 6
            elseif escapes[esc] then
                out[#out + 1] = escapes[esc]
                j = j + 2
            else
                error(("json: bad escape '\\%s' at %d"):format(esc, j))
            end
        else
            out[#out + 1] = c
            j = j + 1
        end
    end
    error("json: unterminated string")
end

local function parseNumber(str, i)
    local numStr = str:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", i)
    local n = tonumber(numStr)
    if not n then error(("json: bad number at %d"):format(i)) end
    return n, i + #numStr
end

local function parseArray(str, i)
    local arr = {}
    local j = skipWhitespace(str, i + 1)
    if str:sub(j, j) == "]" then return arr, j + 1 end
    while true do
        local value
        value, j = parseValue(str, j)
        arr[#arr + 1] = value
        j = skipWhitespace(str, j)
        local c = str:sub(j, j)
        if c == "," then
            j = skipWhitespace(str, j + 1)
        elseif c == "]" then
            return arr, j + 1
        else
            error(("json: expected ',' or ']' at %d"):format(j))
        end
    end
end

local function parseObject(str, i)
    local obj = {}
    local j = skipWhitespace(str, i + 1)
    if str:sub(j, j) == "}" then return obj, j + 1 end
    while true do
        if str:sub(j, j) ~= '"' then
            error(("json: expected string key at %d"):format(j))
        end
        local key
        key, j = parseString(str, j)
        j = skipWhitespace(str, j)
        if str:sub(j, j) ~= ":" then
            error(("json: expected ':' at %d"):format(j))
        end
        j = skipWhitespace(str, j + 1)
        local value
        value, j = parseValue(str, j)
        obj[key] = value
        j = skipWhitespace(str, j)
        local c = str:sub(j, j)
        if c == "," then
            j = skipWhitespace(str, j + 1)
        elseif c == "}" then
            return obj, j + 1
        else
            error(("json: expected ',' or '}' at %d"):format(j))
        end
    end
end

function parseValue(str, i)
    i = skipWhitespace(str, i)
    local c = str:sub(i, i)
    if c == "{" then
        return parseObject(str, i)
    elseif c == "[" then
        return parseArray(str, i)
    elseif c == '"' then
        return parseString(str, i)
    elseif c == "t" then
        if str:sub(i, i + 3) == "true" then return true, i + 4 end
    elseif c == "f" then
        if str:sub(i, i + 4) == "false" then return false, i + 5 end
    elseif c == "n" then
        if str:sub(i, i + 3) == "null" then return nil, i + 4 end
    elseif c == "-" or c:match("%d") then
        return parseNumber(str, i)
    end
    error(("json: unexpected character '%s' at %d"):format(c, i))
end

function Json.decode(str)
    assert(type(str) == "string", "json.decode: expected a string")
    local value, i = parseValue(str, 1)
    i = skipWhitespace(str, i)
    if i <= #str then
        error(("json: trailing content at %d"):format(i))
    end
    return value
end

return Json
