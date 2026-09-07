--- Player-progress persistence: currency and inventory today, and whatever
-- future phases add (skills, quests, unlocked areas, ...) as those systems
-- land. Same paradigm as core/settings.lua -- a loadable Lua chunk, corrupt
-- or missing data degrades to a default instead of propagating -- but a
-- separate file and module, since a save is higher-stakes than a graphics
-- setting and needs structure Settings' own flat, scalars-only serializer
-- was never built to hold.
--
-- Schema changes go through Save.MIGRATIONS rather than editing defaults in
-- place: a new field needs nothing (the defaults-overlay already covers it),
-- but a renamed or reshaped field needs a migration function keyed by the
-- version it upgrades *from*, run in order before validation.

local LuaSerialize = require "utils.luaSerialize"

local Save = {}

Save.FILENAME = "save.lua"
Save.CURRENT_VERSION = 1

Save.defaults = {
    currency = 0,
    inventory = {}, -- index = slot number; an empty slot is `false`, never a hole
    skills = {},    -- id -> { xp = number }; see game/skills.lua
    stats = {       -- lifetime counters, kept across runs
        kills = 0,
        itemsGathered = 0,
        playtime = 0, -- seconds of unpaused play
    },
}

--- keyed by the version a save is upgrading *from*; each mutates the raw
-- decoded table in place. Empty for now -- the first entry lands the day a
-- field is renamed or reshaped, not before.
Save.MIGRATIONS = {}

---@param value any
---@return any
local function clone(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = clone(v) end
    return copy
end

--- an unknown/malformed entry becomes `false` (an explicit empty slot) rather
-- than being dropped, so a later slot doesn't shift into an earlier one's
-- position. The item id isn't checked against the item registry here --
-- Items may not be loaded yet this early in boot -- that happens where the
-- snapshot is actually applied to a live Inventory.
---@param saved any
---@return table
local function validateInventory(saved)
    if type(saved) ~= "table" then return {} end
    local slots = {}
    for i = 1, #saved do
        local slot = saved[i]
        if type(slot) == "table" and type(slot.id) == "string"
            and type(slot.count) == "number" and slot.count > 0 then
            slots[i] = { id = slot.id, count = math.floor(slot.count) }
        else
            slots[i] = false
        end
    end
    return slots
end

---@param saved any
---@return number
local function validateCurrency(saved)
    if type(saved) == "number" and saved >= 0 then return saved end
    return Save.defaults.currency
end

--- a malformed entry for one skill is dropped rather than zeroing the whole
-- table, so a corrupt "mining" doesn't cost the player their "combat" xp
-- too. The skill id isn't checked against the skill registry here, same
-- reasoning as validateInventory and Items -- Skills may not be loaded yet
-- this early in boot.
---@param saved any
---@return table
local function validateSkills(saved)
    if type(saved) ~= "table" then return {} end
    local skills = {}
    for id, entry in pairs(saved) do
        if type(id) == "string" and type(entry) == "table"
            and type(entry.xp) == "number" and entry.xp >= 0 then
            skills[id] = { xp = entry.xp }
        end
    end
    return skills
end

--- defaults first, then whatever the file has on top -- so a counter added
-- in a later version reads as 0 in an old save instead of nil, and one this
-- version no longer tracks still survives the round trip rather than being
-- quietly thrown away
---@param saved any
---@return table
local function validateStats(saved)
    local stats = {}
    for key, value in pairs(Save.defaults.stats) do stats[key] = value end
    if type(saved) ~= "table" then return stats end

    for key, value in pairs(saved) do
        if type(key) == "string" and type(value) == "number" and value >= 0 then
            stats[key] = value
        end
    end
    return stats
end

--- every migration whose index is greater than `fromVersion`, in order
---@param data table # the raw decoded save chunk, mutated in place
---@param fromVersion integer
local function migrate(data, fromVersion)
    for version = fromVersion + 1, Save.CURRENT_VERSION do
        local step = Save.MIGRATIONS[version]
        if step then step(data) end
    end
end

--- defaults overlaid with the saved file. A missing file, an unloadable
-- chunk, or one that errors on run all just hand back fresh defaults --
-- there's no failure mode here that should keep the game from starting. Each
-- field is validated on its own, so a corrupt one falls back without taking
-- the others down with it.
---@return table save
function Save.load()
    local data = nil
    if love.filesystem.getInfo(Save.FILENAME) then
        local chunk = love.filesystem.load(Save.FILENAME)
        if chunk then
            local ok, result = pcall(chunk)
            if ok and type(result) == "table" then data = result end
        end
    end

    if not data then return clone(Save.defaults) end

    local fromVersion = type(data.saveVersion) == "number" and data.saveVersion or 0
    migrate(data, fromVersion)

    return {
        currency = validateCurrency(data.currency),
        inventory = validateInventory(data.inventory),
        skills = validateSkills(data.skills),
        stats = validateStats(data.stats),
    }
end

---@param save table
---@return boolean success
---@return string? err
function Save.save(save)
    save.saveVersion = Save.CURRENT_VERSION
    return love.filesystem.write(Save.FILENAME, "return " .. LuaSerialize.serialize(save) .. "\n")
end

return Save
