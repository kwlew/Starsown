-- lib/utils/format.lua
-- Turning numbers into text the player reads. Locale-aware where it matters:
-- the thousands separator comes from the active language (a comma in English, a
-- period in Spanish and Portuguese), so this can't be a plain gsub at the call
-- site.
--
--   Format.group(1234567)   -- "1,234,567"
--   Format.compact(1234567) -- "1.23M"    (idle-scale readouts)
--   Format.duration(8100)   -- "2h 15m"

local I18n = require "lib.i18n"

local Format = {}

-- Above this, group() hands off to compact(): past seven digits a grouped
-- number stops being something you read and becomes something you measure.
local COMPACT_ABOVE = 1e6

local SUFFIXES = { "K", "M", "B", "T" }

-- Groups the integer part in threes: 1234567 -> "1,234,567".
function Format.group(n)
    local sep = I18n.t("format.thousands")
    local text = tostring(math.floor(n))

    -- Walk right to left in threes. The %1 guard stops the pattern from
    -- prefixing a separator onto the leading group.
    local done
    repeat
        text, done = text:gsub("^(%-?%d+)(%d%d%d)", "%1" .. sep .. "%2")
    until done == 0
    return text
end

-- Three significant figures plus a magnitude suffix. Idle currencies outgrow
-- what a grouped number can say at a glance, and the exact units stop mattering
-- long before that.
function Format.compact(n)
    local sign = n < 0 and "-" or ""
    n = math.abs(n)
    if n < 1000 then return sign .. tostring(math.floor(n)) end

    local unit = 0
    while n >= 1000 and unit < #SUFFIXES do
        n = n / 1000
        unit = unit + 1
    end

    -- Fewer decimals as the mantissa grows, so the string stays about as wide
    -- however big the number gets — a readout that changes width every tick is
    -- what makes an idle HUD twitch.
    local decimals = (n < 10 and 2) or (n < 100 and 1) or 0
    return sign .. string.format("%." .. decimals .. "f", n) .. SUFFIXES[unit]
end

-- Grouped while that is still readable, compact past a million. The default for
-- any currency readout.
function Format.number(n)
    if math.abs(n) >= COMPACT_ABOVE then return Format.compact(n) end
    return Format.group(n)
end

-- Coarse elapsed time: the two largest units that apply, never more. "2h 15m"
-- rather than "2h 15m 3s", because a report about being away for two hours
-- doesn't get better with seconds on it.
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

-- A countdown, always in whole seconds and never below zero. Ceil rather than
-- floor so a timer reads "1s" for the last whole second instead of sitting on
-- "0s" while something is still pending.
function Format.countdown(seconds)
    return math.max(0, math.ceil(seconds))
end

return Format
