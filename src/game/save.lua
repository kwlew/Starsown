-- src/game/save.lua
-- Persists a run to the LÖVE save directory and pays out the time the player
-- spent away. Same shape and the same defensiveness as src/core/settings.lua: the
-- file is a Lua chunk that returns a table, and a missing, corrupt or
-- hand-edited one always yields a playable run rather than an error.
--
--   Save.write(world)          -- -> true on success
--   local world, away = Save.read()
--
-- What is NOT stored is as deliberate as what is. Enemies in flight, shots in
-- the air and the wave timer are all dropped: restoring mid-wave would need the
-- save to describe every enemy's position and health, and the player who closed
-- the game mid-wave would come back to the same emergency they left. A loaded
-- run starts on a fresh intermission with its towers, gold and wave intact.

local Config = require "game.config"
local Map = require "game.map"
local World = require "game.world"

local Save = {}

Save.FILENAME = "run.lua"

-- Bumped when a change to the format makes an older file unreadable. Read()
-- discards anything it doesn't recognise rather than guessing.
Save.VERSION = 1

--------------------------------------------------------------------------------
-- Writing
--------------------------------------------------------------------------------

local function serializeValue(value)
    local t = type(value)
    if t == "string" then return string.format("%q", value) end
    if t == "boolean" then return tostring(value) end
    if t == "number" then
        -- %.14g keeps a float's precision without writing "1.0" for an integer,
        -- and never emits inf/nan in a form the loader can't read back.
        if value ~= value or value == math.huge or value == -math.huge then return "0" end
        return string.format("%.14g", value)
    end
    return "nil"
end

-- Serializes the flat records this file writes: a table of scalars, or an array
-- of such tables. Deliberately not a general-purpose serializer — the save
-- format is fixed and small, and a recursive one would invite it to grow into
-- something the loader below can't validate.
local function serializeRecord(record, keys)
    local parts = {}
    for _, key in ipairs(keys) do
        if record[key] ~= nil then
            parts[#parts + 1] = key .. " = " .. serializeValue(record[key])
        end
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

local TOWER_KEYS = { "type", "col", "row", "level", "spent", "kills" }

function Save.write(world)
    local lines = {
        "-- TD Idle run. Delete this file to start over.",
        "return {",
        "    version = " .. Save.VERSION .. ",",
        "    savedAt = " .. serializeValue(os.time()) .. ",",
        "    gold = " .. serializeValue(world.gold) .. ",",
        "    lives = " .. serializeValue(world.lives) .. ",",
        "    wave = " .. serializeValue(world.wave) .. ",",
        "    bestWave = " .. serializeValue(world.bestWave) .. ",",
        "    elapsed = " .. serializeValue(world.stats.elapsed) .. ",",
        "    goldEarned = " .. serializeValue(world.stats.goldEarned) .. ",",
        "    offlineGold = " .. serializeValue(world.stats.offlineGold) .. ",",
        "    kills = " .. serializeValue(world.stats.kills) .. ",",
        "    leaks = " .. serializeValue(world.stats.leaks) .. ",",
        "    built = " .. serializeValue(world.stats.built) .. ",",
        "    towers = {",
    }

    for _, tower in ipairs(world.towers) do
        lines[#lines + 1] = "        " .. serializeRecord(tower, TOWER_KEYS) .. ","
    end

    lines[#lines + 1] = "    },"
    lines[#lines + 1] = "}"
    lines[#lines + 1] = ""

    return love.filesystem.write(Save.FILENAME, table.concat(lines, "\n"))
end

function Save.exists()
    return love.filesystem.getInfo(Save.FILENAME) ~= nil
end

function Save.delete()
    if Save.exists() then love.filesystem.remove(Save.FILENAME) end
end

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------

local function number(value, fallback, min)
    if type(value) ~= "number" or value ~= value then return fallback end
    if min and value < min then return min end
    return value
end

-- Restores the towers, skipping any entry that no longer describes a legal
-- placement: a tower type removed from the config, a tile that became part of
-- the path, two towers on one tile. Each is silently dropped rather than
-- refunded — a save that disagrees with the current build should degrade, not
-- hand out gold.
local function restoreTowers(world, list)
    if type(list) ~= "table" then return end

    for _, entry in ipairs(list) do
        local def = type(entry) == "table" and Config.towerById[entry.type]
        local col = number(entry.col, nil)
        local row = number(entry.row, nil)

        if def and col and row and Map.isBuildable(col, row) and not world:towerAt(col, row) then
            local tower = {
                type = entry.type,
                col = math.floor(col), row = math.floor(row),
                level = math.floor(number(entry.level, 1, 1)),
                spent = number(entry.spent, def.cost, 0),
                kills = math.floor(number(entry.kills, 0, 0)),
                cooldown = 0,
                angle = 0,
            }
            if tower.level > Config.maxLevel then tower.level = Config.maxLevel end
            world:refresh(tower)

            world.towers[#world.towers + 1] = tower
            world.occupied[tower.row * (Map.COLS + 2) + tower.col] = tower
        end
    end
end

-- Gold for time away, and the seconds it was granted for. Paid against what the
-- run has actually been earning per second rather than a flat rate, so a save
-- that has never killed anything earns nothing — which is the honest answer,
-- and it keeps the payout in step with a run's real progress for free.
--
-- Returns 0, 0 for a gap too short to bother reporting.
function Save.offlineEarnings(world, seconds)
    local o = Config.offline
    if seconds < o.minSeconds then return 0, 0 end

    local counted = math.min(seconds, o.maxHours * 3600)
    local gold = math.floor(world:goldPerSecond() * counted * o.rate)
    if gold <= 0 then return 0, counted end

    return gold, counted
end

-- Loads the saved run, or nil when there isn't a usable one. The second and
-- third results describe the offline payout already credited to the world:
-- gold granted and seconds counted, both 0 when nothing was.
function Save.read()
    if not Save.exists() then return nil end

    local chunk = love.filesystem.load(Save.FILENAME)
    if not chunk then return nil end

    local ok, data = pcall(chunk)
    if not ok or type(data) ~= "table" or data.version ~= Save.VERSION then
        return nil
    end

    local world = World.new()
    world.gold = number(data.gold, Config.economy.startingGold, 0)
    world.lives = math.floor(number(data.lives, Config.economy.startingLives, 1))
    world.wave = math.floor(number(data.wave, 0, 0))
    world.bestWave = math.floor(number(data.bestWave, world.wave, 0))
    if world.bestWave < world.wave then world.bestWave = world.wave end

    world.stats.elapsed = number(data.elapsed, 0, 0)
    world.stats.goldEarned = number(data.goldEarned, 0, 0)
    world.stats.offlineGold = number(data.offlineGold, 0, 0)
    world.stats.kills = math.floor(number(data.kills, 0, 0))
    world.stats.leaks = math.floor(number(data.leaks, 0, 0))
    world.stats.built = math.floor(number(data.built, 0, 0))

    restoreTowers(world, data.towers)

    -- A clock that ran backwards (timezone change, a corrected system clock)
    -- must not pay out, and must not produce a negative gap either.
    local away = math.max(0, os.time() - number(data.savedAt, os.time(), 0))
    local gold, counted = Save.offlineEarnings(world, away)
    world.gold = world.gold + gold

    -- Banked separately from `goldEarned` ON PURPOSE. goldEarned over elapsed is
    -- the rate the payout above is computed from, so folding the payout back
    -- into it would make the rate a function of its own output: close and
    -- reopen twice and the third payout is an order of magnitude too big.
    -- goldEarned stays what towers shot down; this is what time paid.
    world.stats.offlineGold = world.stats.offlineGold + gold

    return world, gold, counted
end

return Save
