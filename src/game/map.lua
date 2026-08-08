-- src/game/map.lua
-- The board: a fixed grid, the path enemies walk, and which tiles a tower may
-- stand on. Everything here is in GRID space — tile (1, 1) is the top-left
-- tile and its center is the point (1, 1). Converting that to pixels is the
-- renderer's job and nothing in this file knows how.
--
--   Map.isPath(col, row)      -- is this tile part of the route?
--   Map.isBuildable(col, row) -- on the board and not on the route
--   Map.positionAt(distance)  -- -> gx, gy, `distance` tiles along the path
--   Map.length                -- total path length, in tiles
--
-- An enemy is stored as a single scalar (how far along the path it is) rather
-- than as a position plus a waypoint index. That makes "which enemy is furthest
-- along" — the targeting rule every tower uses — a plain number comparison, and
-- it makes an enemy's saved state one float.
--
-- The waypoints are authored as tile centers and the first and last sit OUTSIDE
-- the board on purpose, so enemies walk in from off-board and leave the same
-- way rather than blinking into existence on a corner tile.

local Map = {}

Map.COLS, Map.ROWS = 20, 10

-- Corners of the route, in order. Axis-aligned throughout: the path is a grid
-- of tiles, so a diagonal would pass through tile corners and leave gaps that
-- are neither buildable nor walkable-looking.
--
-- The route is drawn to reach into every part of the board — rows 2 through 9
-- of ten, and the full width. A tile's only value is how much path it covers,
-- so a corner the path never approaches isn't spare room, it's board the player
-- can never use. The switchbacks are the other half of that: they fold the
-- route back on itself so one tower in a pocket covers two or three passes.
local WAYPOINTS = {
    { 0, 2 }, { 4, 2 }, { 4, 7 }, { 9, 7 }, { 9, 3 },
    { 14, 3 }, { 14, 9 }, { 18, 9 }, { 18, 5 }, { 21, 5 },
}

-- Built once at require time: the map is a constant, so its geometry is too.
-- segments[i] = { x1, y1, x2, y2, length, start } where `start` is the distance
-- along the whole path at which that segment begins.
local segments = {}
local blocked = {} -- key(col, row) -> true for every tile the route covers

local function key(col, row)
    return row * (Map.COLS + 2) + col
end

-- Marks every tile a straight run covers. Both endpoints are inclusive, so the
-- corner tile shared by two segments is marked by both — harmless, and it means
-- neither segment has to know it is not the first.
local function markSegment(x1, y1, x2, y2)
    local stepX = (x2 > x1 and 1) or (x2 < x1 and -1) or 0
    local stepY = (y2 > y1 and 1) or (y2 < y1 and -1) or 0
    local steps = math.max(math.abs(x2 - x1), math.abs(y2 - y1))

    for i = 0, steps do
        blocked[key(x1 + stepX * i, y1 + stepY * i)] = true
    end
end

local function build()
    local total = 0
    for i = 1, #WAYPOINTS - 1 do
        local a, b = WAYPOINTS[i], WAYPOINTS[i + 1]
        local length = math.abs(b[1] - a[1]) + math.abs(b[2] - a[2]) -- axis-aligned
        segments[i] = {
            x1 = a[1], y1 = a[2], x2 = b[1], y2 = b[2],
            length = length, start = total,
        }
        total = total + length
        markSegment(a[1], a[2], b[1], b[2])
    end
    Map.length = total
end

build()

-- Where the path enters the board, for spawn effects and for the renderer's
-- entry marker. The last waypoint is the exit.
Map.entry = { WAYPOINTS[1][1], WAYPOINTS[1][2] }
Map.exit  = { WAYPOINTS[#WAYPOINTS][1], WAYPOINTS[#WAYPOINTS][2] }

function Map.inBounds(col, row)
    return col >= 1 and col <= Map.COLS and row >= 1 and row <= Map.ROWS
end

function Map.isPath(col, row)
    return blocked[key(col, row)] == true
end

-- A tower may stand here: on the board, and not on the route. Whether a tower
-- is ALREADY here is the world's question, not the map's.
function Map.isBuildable(col, row)
    return Map.inBounds(col, row) and not Map.isPath(col, row)
end

-- The point `distance` tiles along the path, in grid space. Clamped at both
-- ends, so a caller that overshoots gets the exit rather than an error — the
-- world uses the overshoot itself to detect a leak.
function Map.positionAt(distance)
    if distance <= 0 then
        return segments[1].x1, segments[1].y1
    end

    for i = 1, #segments do
        local s = segments[i]
        local into = distance - s.start
        if into <= s.length then
            local t = s.length > 0 and (into / s.length) or 0
            return s.x1 + (s.x2 - s.x1) * t, s.y1 + (s.y2 - s.y1) * t
        end
    end

    local last = segments[#segments]
    return last.x2, last.y2
end

-- The route as a flat list of grid points, for drawing it in one polyline.
-- Built once; the renderer scales it to pixels every frame but never rebuilds it.
function Map.outline()
    if not Map.cachedOutline then
        local points = {}
        for _, w in ipairs(WAYPOINTS) do
            points[#points + 1] = w[1]
            points[#points + 1] = w[2]
        end
        Map.cachedOutline = points
    end
    return Map.cachedOutline
end

-- Every buildable tile, for anything that needs to reason about the board as a
-- whole (a "build best tower" helper, an AI, a heat map). Cheap and built once.
function Map.buildableTiles()
    if not Map.cachedBuildable then
        local tiles = {}
        for row = 1, Map.ROWS do
            for col = 1, Map.COLS do
                if not Map.isPath(col, row) then
                    tiles[#tiles + 1] = { col = col, row = row }
                end
            end
        end
        Map.cachedBuildable = tiles
    end
    return Map.cachedBuildable
end

return Map
