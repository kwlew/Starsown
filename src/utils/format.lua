--- Numbers to player-facing text. Locale-free; pass the separator.

local Format = {}

local COMPACT_ABOVE = 1e6
local SUFFIXES = { "K", "M", "B", "T" }

--- digits in threes: group(1234567, ",") -> "1,234,567"
---@param n number
---@param separator? string # defaults to ","
---@return string
function Format.group(n, separator)
    separator = separator or ","
    local text, done = tostring(math.floor(n)), nil
    repeat
        text, done = text:gsub("^(%-?%d+)(%d%d%d)", "%1" .. separator .. "%2")
    until done == 0
    return text
end

--- three significant figures plus a suffix: "1.23M"
---@param n number
---@return string
function Format.compact(n)
    local sign = n < 0 and "-" or ""
    n = math.abs(n)
    if n < 1000 then return sign .. tostring(math.floor(n)) end

    local unit = 0
    while n >= 1000 and unit < #SUFFIXES do
        n, unit = n / 1000, unit + 1
    end
    local decimals = (n < 10 and 2) or (n < 100 and 1) or 0
    return sign .. string.format("%." .. decimals .. "f", n) .. SUFFIXES[unit]
end

--- grouped up to seven digits, compact past that
---@param n number
---@param separator? string
---@return string
function Format.number(n, separator)
    if math.abs(n) >= COMPACT_ABOVE then --- whole seconds left, rounded up; never below 0
---@param seconds number
---@return integer
function Format.countdown(seconds)
    return math.max(0, math.ceil(seconds))
end

return Format.compact(n) end
    --- whole seconds left, rounded up; never below 0
---@param seconds number
---@return integer
function Format.countdown(seconds)
    return math.max(0, math.ceil(seconds))
end

return Format.group(n, separator)
end

--- the two largest units: "2h 15m", "4m 3s", "9s"
---@param seconds number
---@return string
function Format.duration(seconds)
    seconds = math.max(0, math.floor(seconds))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor(seconds % 3600 / 60)
    if hours > 0 then
        return minutes > 0 and (hours .. "h " .. minutes .. "m") or (hours .. "h")
    end
    if minutes > 0 then return minutes .. "m " .. (seconds % 60) .. "s" end
    return seconds .. "s"
end

--- whole seconds left, rounded up; never below 0
---@param seconds number
---@return integer
function Format.countdown(seconds)
    return math.max(0, math.ceil(seconds))
end

return Format
