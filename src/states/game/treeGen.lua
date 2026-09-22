-- src/states/game/treeGen.lua
-- Tree generation.

local Noise = require "utils.noise"
local Biomes = require "states.game.biomes"

local TreeGen = {}

TreeGen.SPACING = 2.6 -- minimum distance between the actual trunk positions, in meters
local JITTER = 0.28 -- stays inside the owning tile, including at chunk boundaries
local REACH = math.floor(TreeGen.SPACING + JITTER * 2)

function TreeGen.position(seed, col, row)
    return col + 0.5 + (Noise.hash(col, row, seed + 7100) * 2 - 1) * JITTER,
           row + 0.5 + (Noise.hash(col, row, seed + 7200) * 2 - 1) * JITTER
end

local ROLL_SALT = 7000 -- keeps this seed's rolls unrelated to the biome noise
local GROVE_SALT = 8000
local GROVE_SCALE = 7 -- meters per grove noise cell
local GROVE_MIN, GROVE_SPAN = 0.15, 1.7 -- opens gaps between small groups of trees

local maxDensity = 0
for _, spec in ipairs(Biomes.all()) do maxDensity = math.max(maxDensity, spec.trees) end
local CHEAP_REJECT = maxDensity * (GROVE_MIN + GROVE_SPAN) -- no tile can ever roll above this

local function roll(seed, col, row)
    return Noise.hash(col, row, seed + ROLL_SALT)
end

--- the roll a tile has to beat to be a candidate
local function rate(map, seed, col, row)
    local grove = GROVE_MIN + GROVE_SPAN * Noise.fbm(col / GROVE_SCALE, row / GROVE_SCALE, seed + GROVE_SALT, 2)
    return Biomes.treeDensity(map.vegetation(col, row)) * grove
end

--- whether tile A is settled before tile B: lower roll first, the tile's own coordinates breaking a tie
local function before(rollA, colA, rowA, rollB, colB, rowB)
    if rollA ~= rollB then return rollA < rollB end
    if colA ~= colB then return colA < colB end
    return rowA < rowB
end

--- Whether a tile grows a tree. `settled` caches answers within a query or chunk.
local function grows(map, seed, col, row, settled)
    local id = col .. ":" .. row
    local known = settled[id]
    if known ~= nil then return known end

    local mine = roll(seed, col, row)
    local result = mine < CHEAP_REJECT and mine < rate(map, seed, col, row)
    if result then
        local x, y = TreeGen.position(seed, col, row)
        for dr = -REACH, REACH do
            for dc = -REACH, REACH do
                if dc ~= 0 or dr ~= 0 then
                    local oc, or_ = col + dc, row + dr
                    local other = roll(seed, oc, or_)
                    -- only a tile settled earlier can block us; check the cheap roll before its biome
                    if other < CHEAP_REJECT and before(other, oc, or_, mine, col, row) then
                        local ox, oy = TreeGen.position(seed, oc, or_)
                        if (ox - x) ^ 2 + (oy - y) ^ 2 < TreeGen.SPACING ^ 2
                            and grows(map, seed, oc, or_, settled) then
                            result = false
                            break
                        end
                    end
                end
            end
            if not result then break end
        end
    end
    settled[id] = result
    return result
end

--- The species growing on a tile, if any.
---@param map table # a Biomes map
---@param seed integer
---@param col integer
---@param row integer
---@param settled table? # optional cache belonging to this map/seed only
---@return string? species
function TreeGen.at(map, seed, col, row, settled)
    if roll(seed, col, row) >= CHEAP_REJECT then return nil end -- most tiles end here, allocating nothing
    if grows(map, seed, col, row, settled or {}) then return "oak" end
end

return TreeGen
