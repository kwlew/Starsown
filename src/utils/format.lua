--- Turning numbers into text the player reads. Locale-aware where it
-- matters: the thousands separator comes from the active language (comma in
-- English, period in Spanish/Portuguese), so this can't be a plain gsub at the call site.
--
--   Format.group(1234567)   -- "1,234,567"
--   Format.compact(1234567) -- "1.23M"    (idle-scale readouts)
--   Format.duration(8100)   -- "2h 15m"

local I18n = require "core.i18n"

local Format = {}

local COMPACT_ABOVE = 1e6 -- past seven digits, group() hands off to compact()

local SUFFIXES = { "K", "M", "B", "T" }

--- digits in threes, split by the active language's thousands separator
---@param n number # truncated to an integer
---@return string
function Format.group(n)
    local sep = I18n.t("format.thousands")
    local text = tostring(math.floor(n))

    local done
    repeat
        text, done = text:gsub("^(%-?%d+)(%d%d%d)", "%1" .. sep .. "%2") -- walk right to left in threes
    until done == 0
    return text
end

--- three significant figures plus a magnitude suffix, for numbers a grouped string can't say at a glance
---@param n number
---@return string
function Format.compact(n)
    local sign = n < 0 and "-" or ""
    n = math.abs(n)
    if n < 1000 then return sign .. tostring(math.floor(n)) end

    local unit = 0
    while n >= 1000 and unit < #SUFFIXES do
        n = n / 1000
        unit = unit + 1
    end

    local decimals = (n < 10 and 2) or (n < 100 and 1) or 0
    return sign .. string.format("%." .. decimals .. "f", n) .. SUFFIXES[unit]
end

--- the general readout: grouped up to seven digits, compact past that
---@param n number
---@return string
function Format.number(n)
    if math.abs(n) >= COMPACT_ABOVE then return Format.compact(n) end
    return Format.group(n)
end

--- the two largest units that apply, never more: "2h 15m" not "2h 15m 3s"
---@param seconds number
---@return string
function Format.duration(seconds)
    seconds = math.max(0, math.floor(seconds))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor(seconds % 3600 / 60)

    if hours > 0 then
        return minutes > 0 and (hours .. "h " .. minutes .. "m") or (hours .. "h")
    end
    if minutes > 0 then
        return minutes .. "m " .. (seconds % 60) .. "s"
    end
    return seconds .. "s"
end

--- ceil, not floor, so a timer reads "1s" through the last whole second instead of sitting on "0s"
---@param seconds number
---@return integer # whole seconds remaining, never below 0
function Format.countdown(seconds)
    return math.max(0, math.ceil(seconds))
end

return Format
