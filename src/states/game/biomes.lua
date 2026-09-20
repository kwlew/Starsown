-- src/states/game/biomes.lua
-- Which biome a tile (one square meter) belongs to. Biomes are data (`color` names a key in
-- palette.biomes; display names would come from biomes.* in game.json). This
-- decides where each one is; treeGen.lua reads their tree density.
--
-- A single smooth "vegetation" value decides the biome, sorted by `below`:
-- because it varies continuously, dense forest can only sit next to forest,
-- never straight against plains, and regions come out as blobs, not specks.
-- The map is a pure function of the seed, so it needs no storage and works
-- over the unbounded world in any sampling order.

local Noise = require "utils.noise"
local Math = require "utils.math"

local Biomes = {}

-- Ordered by `below`: a tile takes the first biome whose limit its vegetation is
-- under. `trees` is the chance a tile is a tree candidate (see treeGen.lua).
local specs = {
    { id = "plains",            below = 0.47,       color = "plains",        trees = 0.005 },
    { id = "forest",            below = 0.60,       color = "forest",        trees = 0.03 },
    { id = "dense_forest",      below = math.huge,  color = "denseForest",   trees = 0.15 },
}

local BY_ID = {}
for _, spec in ipairs(specs) do BY_ID[spec.id] = spec end

local SCALE = 40 -- Size of biomes.
local OCTAVES = 3 -- How many layers of noise.
local WARP = 0.7 -- how far the edges are pushed off straight noise contours, in cells
local SPAWN_RADIUS = 24 -- meters around (0, 0) kept open so a run starts in plains
local SPAWN_BIAS = 0.6 -- how much vegetation is subtracted at the very center

---@param id string
---@return table? spec
function Biomes.get(id)
    return BY_ID[id]
end

---@return table[] # in order, plains first
function Biomes.all()
    return specs
end

--- A biome map for one seed.
---@param seed integer
---@return { seed: integer, at: fun(col: integer, row: integer): string, vegetation: fun(col: integer, row: integer): number }
function Biomes.new(seed)
    local map = { seed = seed }

    --- the 0..1 vegetation value; higher is denser
    function map.vegetation(col, row)
        local x, y = (col + 0.5) / SCALE, (row + 0.5) / SCALE
        -- offsets in the seed keep the two warp fields unrelated to each other and to the base
        local wx = (Noise.fbm(x, y, seed + 1000, 2) - 0.5) * 2 * WARP
        local wy = (Noise.fbm(x, y, seed + 2000, 2) - 0.5) * 2 * WARP
        local value = Noise.fbm(x + wx, y + wy, seed, OCTAVES)
        local spawn = Math.clamp01(1 - Math.length(col + 0.5, row + 0.5) / SPAWN_RADIUS)
        return value - SPAWN_BIAS * spawn
    end

    ---@return string id
    function map.at(col, row)
        local vegetation = map.vegetation(col, row)
        for _, spec in ipairs(specs) do
            if vegetation < spec.below then return spec.id end
        end
        return specs[#specs].id
    end

    return map
end

return Biomes
