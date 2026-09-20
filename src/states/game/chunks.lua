-- src/states/game/chunks.lua
-- The streamed part of the world: trees, generated a chunk at a time around the
-- camera and dropped when it moves away. Generation itself is pure (treeGen.lua),
-- so the only thing that has to be remembered is what the player changed - a
-- felled tree stays gone, a stump stays a stump - and that is kept per tile,
-- outside the chunks, so it survives them unloading.

local Tree = require "states.game.tree"
local TreeGen = require "states.game.treeGen"

local Chunks = {}
Chunks.__index = Chunks

Chunks.SIZE = 16 -- tiles per chunk side

local KEY_OFFSET = 2 ^ 24 -- offset and stride so (a, b) packs into one exact number

local function key(a, b)
    return (a + KEY_OFFSET) * (KEY_OFFSET * 2) + (b + KEY_OFFSET)
end

---@param world table # needs .seed and .biomes
function Chunks.new(world)
    return setmetatable({ world = world, loaded = {}, changes = {}, scratch = {} }, Chunks)
end

--- Whether a tree grows on a tile and hasn't been cleared - true for a stump
-- too, since it still blocks. Needs no loaded chunk.
---@return boolean
function Chunks:isTreeAt(col, row)
    return self.changes[key(col, row)] ~= "removed"
        and TreeGen.at(self.world.biomes, self.world.seed, col, row) ~= nil
end

local function generate(self, cx, cy)
    local size = Chunks.SIZE
    local chunk = { cx = cx, cy = cy, trees = {}, byTile = {} }
    for row = cy * size, cy * size + size - 1 do
        for col = cx * size, cx * size + size - 1 do
            local tile = key(col, row)
            local species = self.changes[tile] ~= "removed"
                and TreeGen.at(self.world.biomes, self.world.seed, col, row)
            if species then
                local tree = Tree.new(col, row, species)
                if self.changes[tile] == "stump" then tree:becomeStump() end
                chunk.trees[#chunk.trees + 1] = tree
                chunk.byTile[tile] = tree
            end
        end
    end
    return chunk
end

--- Loads the chunks within `radius` of a world position and unloads the ones
-- beyond it; at most `budget` new chunks per call, nearest first, so covering
-- a new stretch of ground spreads over a few frames instead of one hitch.
---@param x number # meters
---@param y number
---@param radius integer # in chunks
---@param budget number
function Chunks:stream(x, y, radius, budget)
    local size = Chunks.SIZE
    local ccx, ccy = math.floor(x / size), math.floor(y / size)

    for id, chunk in pairs(self.loaded) do
        if math.max(math.abs(chunk.cx - ccx), math.abs(chunk.cy - ccy)) > radius + 1 then
            self.loaded[id] = nil
        end
    end

    local missing = self.scratch
    for i = #missing, 1, -1 do missing[i] = nil end
    for cy = ccy - radius, ccy + radius do
        for cx = ccx - radius, ccx + radius do
            if not self.loaded[key(cx, cy)] then
                missing[#missing + 1] = { cx, cy, (cx - ccx) ^ 2 + (cy - ccy) ^ 2 }
            end
        end
    end
    table.sort(missing, function(a, b) return a[3] < b[3] end)

    for i = 1, math.min(#missing, budget) do
        local cx, cy = missing[i][1], missing[i][2]
        self.loaded[key(cx, cy)] = generate(self, cx, cy)
    end
end

--- Fills `out` with the loaded trees inside a rectangle (meters), clearing it first.
---@param out table
---@return table out
function Chunks:collect(out, left, top, right, bottom)
    for i = #out, 1, -1 do out[i] = nil end
    local size = Chunks.SIZE
    for cy = math.floor(top / size), math.floor(bottom / size) do
        for cx = math.floor(left / size), math.floor(right / size) do
            local chunk = self.loaded[key(cx, cy)]
            if chunk then
                for _, tree in ipairs(chunk.trees) do
                    if tree.x >= left and tree.x <= right and tree.y >= top and tree.y <= bottom then
                        out[#out + 1] = tree
                    end
                end
            end
        end
    end
    return out
end

local function chunkOf(self, col, row)
    local size = Chunks.SIZE
    return self.loaded[key(math.floor(col / size), math.floor(row / size))]
end

--- Records that a tree became a stump, or (removed) is gone for good.
---@param tree table
---@param removed boolean
function Chunks:changed(tree, removed)
    local tile = key(tree.col, tree.row)
    self.changes[tile] = removed and "removed" or "stump"
    if not removed then return end

    local chunk = chunkOf(self, tree.col, tree.row)
    if not chunk then return end
    chunk.byTile[tile] = nil
    for i, other in ipairs(chunk.trees) do
        if other == tree then table.remove(chunk.trees, i) break end
    end
end

---@return integer chunks
---@return integer trees
function Chunks:stats()
    local chunks, trees = 0, 0
    for _, chunk in pairs(self.loaded) do
        chunks, trees = chunks + 1, trees + #chunk.trees
    end
    return chunks, trees
end

return Chunks
