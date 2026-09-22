-- src/states/game/spawn.lua
-- Where a new run puts the player, Minecraft-style: a random tile inside a
-- RANGE x RANGE square around (0, 0), and it has to be free. Tiles are tried in
-- a random order that depends only on the world seed, so a seed always spawns
-- in the same place. If no comfortable tile turns up, the least crowded one in
-- the whole square is used instead - blocked tiles only as a last resort.
--
-- Nothing here knows what blocks a tile; the caller passes that in, so trees
-- today and water or buildings later need no change here.

local Noise = require "utils.noise"

local Spawn = {}

Spawn.RANGE = 128 -- tiles per side of the search square, centered on (0, 0)

local ATTEMPTS = 64 -- random tiles tried before scanning the whole square
local CROWD_RADIUS = 2 -- tiles around a candidate counted when ranking them
local BLOCKED_PENALTY = 1000 -- outweighs any crowd, so a free tile always ranks above a blocked one

local HALF = Spawn.RANGE / 2

---@param i integer # which attempt
---@param seed integer
---@return integer col
---@return integer row
local function randomTile(i, seed)
    return math.floor(Noise.hash(i, 0, seed) * Spawn.RANGE) - HALF,
           math.floor(Noise.hash(i, 1, seed) * Spawn.RANGE) - HALF
end

--- free, and every neighbor free too, so the player isn't spawned wedged in
local function isOpen(blocked, col, row)
    for dr = -1, 1 do
        for dc = -1, 1 do
            if blocked(col + dc, row + dr) then return false end
        end
    end
    return true
end

--- lower is freer: a blocked tile is far worse than any crowd, then fewer blocked neighbors wins
local function crowding(blocked, col, row)
    local score = blocked(col, row) and BLOCKED_PENALTY or 0
    for dr = -CROWD_RADIUS, CROWD_RADIUS do
        for dc = -CROWD_RADIUS, CROWD_RADIUS do
            if (dc ~= 0 or dr ~= 0) and blocked(col + dc, row + dr) then score = score + 1 end
        end
    end
    return score
end

--- The spawn tile for a world.
---@param seed integer
---@param blocked fun(col: integer, row: integer): boolean # true where the player can't stand
---@return integer col
---@return integer row
function Spawn.find(seed, blocked)
    for i = 1, ATTEMPTS do
        local col, row = randomTile(i, seed)
        if isOpen(blocked, col, row) then return col, row end
    end

    -- nowhere comfortable by luck: rank the whole square, ties going to the tile closest to (0, 0)
    local bestCol, bestRow, bestScore, bestDist = 0, 0, math.huge, math.huge
    for row = -HALF, HALF - 1 do
        for col = -HALF, HALF - 1 do
            local score = crowding(blocked, col, row)
            local dist = col * col + row * row
            if score < bestScore or (score == bestScore and dist < bestDist) then
                bestCol, bestRow, bestScore, bestDist = col, row, score, dist
            end
        end
    end
    return bestCol, bestRow
end

return Spawn
