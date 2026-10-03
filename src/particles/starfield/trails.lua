--- Every shooting-star trail in one shared mesh, one draw call.

local Look = require("particles.starfield.look")

local Trails = {}

local SEGMENTS = 12
local CORE_W = 2.5    -- half-width at the head, px
local FEATHER = 1.5   -- soft edge each side, px
local WIDTH_RAMP = 60 -- short trails taper thinner
local FADE_POW = 1.6

local VERTS = (SEGMENTS + 1) * 4
local INDICES = SEGMENTS * 3 * 6

local mesh, verts
local capacity = 0
local count = 0

--- grows the shared buffer, prebuilding its index map
---@param needed integer
function Trails.reserve(needed)
    if capacity >= needed then return end
    capacity = math.max(needed, capacity * 2, 16)

    local newVerts, map = {}, {}
    for t = 0, capacity - 1 do
        local base = t * VERTS
        for _ = 1, VERTS do newVerts[#newVerts + 1] = { 0, 0, 0, 0, 1, 1, 1, 1 } end
        for i = 0, SEGMENTS - 1 do
            local a, b = base + i * 4, base + (i + 1) * 4
            for row = 1, 3 do -- edge, core, core, edge strips
                map[#map + 1] = a + row
                map[#map + 1] = a + row + 1
                map[#map + 1] = b + row + 1
                map[#map + 1] = a + row
                map[#map + 1] = b + row + 1
                map[#map + 1] = b + row
            end
        end
    end
    mesh = love.graphics.newMesh(newVerts, "triangles")
    mesh:setVertexMap(map)
    verts = newVerts
end

local function setVertex(v, x, y, r, g, b, a)
    v[1], v[2] = x, y
    v[5], v[6], v[7], v[8] = r, g, b, a
end

--- queues one tapering streak behind the star's head
---@param s table
---@param length number
---@param fade number # 0..1
function Trails.add(s, length, r, g, b, fade)
    if count >= capacity then return end
    local base = count * VERTS
    count = count + 1

    local dx, dy = s.dirX, s.dirY
    local nx, ny = -dy, dx
    local coreW = CORE_W * math.min(1, length / WIDTH_RAMP) * s.scale
    local nose = math.min(coreW + FEATHER, length) -- reaches just ahead of the head

    for i = 0, SEGMENTS do
        local t, shape
        if i == 0 then
            t, shape = -nose / length, 0
        else
            t = (i - 1) / (SEGMENTS - 1)
            shape = 1 - t
        end
        local px, py = s.x - dx * length * t, s.y - dy * length * t
        local core, edge = coreW * shape, coreW * shape + FEATHER
        local alpha = shape ^ FADE_POW * fade

        local sr, sg, sb = r, g, b
        if s.rainbow then sr, sg, sb = Look.trailHue(s, t) end

        local o = base + i * 4
        setVertex(verts[o + 1], px + nx * edge, py + ny * edge, sr, sg, sb, 0)
        setVertex(verts[o + 2], px + nx * core, py + ny * core, sr, sg, sb, alpha)
        setVertex(verts[o + 3], px - nx * core, py - ny * core, sr, sg, sb, alpha)
        setVertex(verts[o + 4], px - nx * edge, py - ny * edge, sr, sg, sb, 0)
    end
end

--- draws what was queued this frame, then empties the queue
function Trails.flush()
    if count == 0 then return end
    mesh:setVertices(verts, 1, count * VERTS)
    mesh:setDrawRange(1, count * INDICES)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(mesh)
    count = 0
end

return Trails
