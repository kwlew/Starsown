--- Generates star-chart figures: clustered stars linked by a spanning tree.

local Geometry = require("particles.stars.geometry")
local Math = require("utils.math")

local Constellations = {}

local EDGE_MARGIN_X, EDGE_MARGIN_Y = 0.05, 0.08 -- of the sky; survives cropping
local MAX_DEGREE = 3    -- links per star before it reads as a web
local MAX_LINK = 1.8    -- x link distance
local MIN_SPACING = 0.5 -- x link distance
local PLACE_TRIES = 40
local MIN_STARS, MIN_LINKS = 4, 3

---@param keepOut number[][]
---@return boolean
local function blocked(keepOut, x, y)
    for _, rect in ipairs(keepOut) do
        if Geometry.inRect(x, y, rect) then return true end
    end
    return false
end

---@return boolean
local function canLink(keepOut, points, edges, i, j)
    local a, b = points[i], points[j]
    for _, rect in ipairs(keepOut) do
        if Geometry.segmentHitsRect(a.x, a.y, b.x, b.y, rect) then return false end
    end
    for _, e in ipairs(edges) do
        local c, d = points[e[1]], points[e[2]]
        if Geometry.segmentsCross(a.x, a.y, b.x, b.y, c.x, c.y, d.x, d.y) then return false end
    end
    return true
end

--- links between two stars along the tree
---@return integer
local function treeHops(count, edges, from, to)
    local hops, queue, head = { [from] = 0 }, { from }, 1
    while head <= #queue do
        local node = queue[head]
        head = head + 1
        for _, e in ipairs(edges) do
            local other = e[1] == node and e[2] or e[2] == node and e[1] or nil
            if other and not hops[other] then
                hops[other] = hops[node] + 1
                queue[#queue + 1] = other
            end
        end
    end
    return hops[to] or count
end

---@param cfg table
---@param placed table[] # earlier constellations
---@return number|nil x
---@return number|nil y
local function findCenter(cfg, placed, radius, w, h)
    local mx, my = w * EDGE_MARGIN_X, h * EDGE_MARGIN_Y
    for _ = 1, PLACE_TRIES do
        local x, y = Math.randRange(mx, w - mx), Math.randRange(my, h - my)
        local clear = not blocked(cfg.keepOut, x, y)
        for _, c in ipairs(placed) do
            if clear and Math.length(x - c.x, y - c.y) < radius + c.radius + cfg.gap then clear = false end
        end
        if clear then return x, y end
    end
end

--- scatters spaced points in a tilted ellipse
---@return table[]
local function scatter(cfg, cx, cy, radius, count, w, h)
    local mx, my = w * EDGE_MARGIN_X, h * EDGE_MARGIN_Y
    local tilt, aspect = Math.randAngle(), Math.randRange(0.45, 1)
    local cosT, sinT = math.cos(tilt), math.sin(tilt)
    local points = {}
    for _ = 1, count * 25 do
        if #points == count then break end
        local angle, dist = Math.randAngle(), radius * math.sqrt(math.random())
        local ox, oy = math.cos(angle) * dist, math.sin(angle) * dist * aspect
        local x, y = cx + ox * cosT - oy * sinT, cy + ox * sinT + oy * cosT
        local ok = x > mx and x < w - mx and y > my and y < h - my and not blocked(cfg.keepOut, x, y)
        for _, p in ipairs(points) do
            if not ok then break end
            ok = Math.length(x - p.x, y - p.y) >= cfg.link * MIN_SPACING
        end
        if ok then points[#points + 1] = { x = x, y = y } end
    end
    return points
end

--- shortest non-crossing links first, capped per star
---@return table edges
---@return table inTree
---@return table degree
---@return table depth
local function spanningTree(cfg, points)
    local inTree, degree, depth, edges = { [1] = true }, {}, { [1] = 0 }, {}
    for i = 1, #points do degree[i] = 0 end
    while true do
        local best, bi, bj = cfg.link * MAX_LINK, nil, nil
        for i = 1, #points do
            if inTree[i] and degree[i] < MAX_DEGREE then
                for j = 1, #points do
                    local d = Math.length(points[i].x - points[j].x, points[i].y - points[j].y)
                    if not inTree[j] and d < best and canLink(cfg.keepOut, points, edges, i, j) then
                        best, bi, bj = d, i, j
                    end
                end
            end
        end
        if not bi then break end
        inTree[bj] = true
        degree[bi], degree[bj] = degree[bi] + 1, degree[bj] + 1
        depth[bj] = depth[bi] + 1
        edges[#edges + 1] = { bi, bj }
    end
    return edges, inTree, degree, depth
end

--- sometimes closes one loop over three or more stars
local function addLoop(cfg, points, edges, inTree, degree, depth)
    if math.random() >= cfg.loopChance then return end
    local best, bi, bj = cfg.link * MAX_LINK, nil, nil
    for i = 1, #points do
        for j = i + 1, #points do
            local d = Math.length(points[i].x - points[j].x, points[i].y - points[j].y)
            if inTree[i] and inTree[j] and d < best
                and degree[i] < MAX_DEGREE and degree[j] < MAX_DEGREE
                and treeHops(#points, edges, i, j) >= 3 and canLink(cfg.keepOut, points, edges, i, j) then
                best, bi, bj = d, i, j
            end
        end
    end
    if not bi then return end
    if depth[bi] < depth[bj] then bi, bj = bj, bi end -- grow from the later-traced end
    edges[#edges + 1] = { bi, bj }
end

--- one figure, or nil if it didn't fit
---@param cfg table # { link, gap, loopChance, starsMin, starsMax, keepOut }
---@param placed table[]
---@param w number
---@param h number
---@return table|nil # { x, y, radius, points, links }
function Constellations.generate(cfg, placed, w, h)
    local count = Math.randInt(cfg.starsMin, cfg.starsMax)
    local radius = cfg.link * math.sqrt(count) * 0.6
    local cx, cy = findCenter(cfg, placed, radius, w, h)
    if not cx then return nil end

    local points = scatter(cfg, cx, cy, radius, count, w, h)
    if #points < MIN_STARS then return nil end

    local edges, inTree, degree, depth = spanningTree(cfg, points)
    if #edges < MIN_LINKS then return nil end
    addLoop(cfg, points, edges, inTree, degree, depth)

    local figure = { x = cx, y = cy, radius = radius, points = {}, links = {} }
    for i, p in ipairs(points) do
        if inTree[i] then figure.points[#figure.points + 1] = p end
    end
    for _, e in ipairs(edges) do
        local a, b = points[e[1]], points[e[2]]
        figure.links[#figure.links + 1] = { a.x, a.y, b.x, b.y, depth = depth[e[1]] }
    end
    return figure
end

return Constellations
