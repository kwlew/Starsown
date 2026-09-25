--- Fixed night sky behind the loading screen and menu: twinkling stars plus a
-- few constellations linking some of them.

local Theme = require "ui.core.theme"
local Math = require "utils.math"
local Motion = require "ui.core.motion"
local Ease = require "utils.ease"
local Sky = require "particles.sky"

local Stars = {}
Stars.__index = Stars

-- one textured quad per star rather than a point, since point size is fixed
-- per draw call and can't vary star to star
local STAR_VERTEX_FORMAT = {
    { "VertexPosition", "float", 2 },
    { "VertexTexCoord", "float", 2 },
    { "StarData", "float", 3 }, -- brightness, blink phase, blink speed
    { "StarTint", "float", 2 }, -- accent (0) or accentAlt (1), how far toward it
}

local SPRITE_SIZE = 64
local SPRITE_CORE = 0.16 -- core radius as a fraction of the sprite's half-width; the rest is halo
local QUAD_CORNERS = { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, -1 }, { 1, 1 }, { -1, 1 } }

-- design-space fractions {x0, y0, x1, y1} that the main menu's title and
-- button column cover; constellations keep their stars and lines out of them.
-- The two touch so nothing squeezes in under the splash text.
local KEEP_OUT = {
    { 0.25, 0.04, 0.75, 0.34 }, -- title + splash
    { 0.33, 0.34, 0.67, 0.90 }, -- menu
}
local KEEP_OUT_PAD = 28 -- design px of clearance around each, so lines don't graze the UI

-- constellation stars stay this far in from the sky's edges, so the crop a
-- non-16:9 window takes doesn't cut them in half
local EDGE_MARGIN_X, EDGE_MARGIN_Y = 0.05, 0.08

local MAX_DEGREE = 3 -- more links than this on one star reads as a web, not a figure
local MAX_LINK = 1.8 -- x constellationLink; farther stars are dropped rather than linked
local MIN_SPACING = 0.5 -- x constellationLink
local PLACE_TRIES = 40

-- a new sky draws its constellations in, each growing out from its first star
-- along the tree, so branches extend together rather than one link at a time
local TRACE_DELAY = 0.4 -- s, lets the sky's own fade-in land first
local TRACE_STAGGER = 0.35 -- s between one constellation starting and the next
local TRACE_LINK = 0.28 -- s to draw one link

local HOVER_REACH = 80 -- design px from a line that counts as pointing at it
local HOVER_RATE = 8 -- how fast a constellation lights up and settles back
local HOVER_ALPHA = 0.6 -- line alpha fully lit, up from lineAlpha

local twinkleShader
local sprite

--- built on first use and shared. The twinkle and tint run in the vertex
-- shader off per-star attributes, so the whole sky is one draw call with no
-- per-frame work on the CPU. Tints arrive as uniforms rather than baked vertex
-- colours so a theme switch recolours the sky without a rebuild.
---@return any # a love.Shader
local function getTwinkleShader()
    if not twinkleShader then
        twinkleShader = love.graphics.newShader([[
            vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
            {
                return Texel(texture, texture_coords) * color;
            }
        ]], [[
            attribute vec3 StarData;
            attribute vec2 StarTint;

            extern number time;
            extern number oscillation;
            extern vec3 tintA;
            extern vec3 tintB;

            vec4 position(mat4 transform_projection, vec4 vertex_position)
            {
                number brightness = clamp(
                    StarData.x + sin(StarData.y + time * StarData.z) * oscillation,
                    0.0, 1.0);
                vec3 tint = mix(tintA, tintB, StarTint.x);
                VaryingColor.rgb *= mix(vec3(1.0), tint, StarTint.y) * brightness;
                return transform_projection * vertex_position;
            }
        ]])
    end
    return twinkleShader
end

--- a solid round core with a faint halo past it, generated once. The core
-- edge is a short ramp rather than a hard cut so a star under two pixels
-- across still reads round.
---@return any # a love.Image
local function getSprite()
    if sprite then return sprite end
    local data = love.image.newImageData(SPRITE_SIZE, SPRITE_SIZE)
    local center = (SPRITE_SIZE - 1) / 2
    data:mapPixel(function(x, y)
        local d = Math.length(x - center, y - center) / center
        if d >= 1 then return 1, 1, 1, 0 end
        local core = 1 - Math.clamp01((d - SPRITE_CORE * 0.6) / (SPRITE_CORE * 0.8))
        local halo = 0.22 * math.exp(-(d / 0.4) ^ 2) * (1 - d)
        return 1, 1, 1, math.max(core, halo)
    end)
    sprite = love.graphics.newImage(data)
    sprite:setFilter("linear", "linear")
    return sprite
end

---@param color number[] # RGB
---@return number[] # the same hue at full strength, so a dark accent tints instead of dimming
local function normalized(color)
    local peak = math.max(color[1], color[2], color[3], 1e-6)
    return { color[1] / peak, color[2] / peak, color[3] / peak }
end

---@param config? table # every field below may be overridden
---@return table
function Stars.new(config)
    config = config or {}
    return setmetatable({
        stars = {},
        segments = {}, -- every constellation line: { x1, y1, x2, y2, group = constellation index, depth = tree depth it grows from }
        constellations = {}, -- { x, y, radius, glow } of each placed one; glow is 0..1 hover light
        pointerX = nil, -- design-space pointer, nil when nothing is pointing at the sky
        pointerY = nil,
        mesh = nil,
        time = 0,
        amountMin = config.amountMin or 150,
        amountMax = config.amountMax or 190,
        brightnessOscillation = config.brightnessOscillation or 0.7,
        blinkSpeedMin = config.blinkSpeedMin or 0.3,
        blinkSpeedMax = config.blinkSpeedMax or 1.2,
        sizeMin = config.sizeMin or 0.9, -- core radius, design px
        sizeMax = config.sizeMax or 2.4,
        featuredSizeMin = config.featuredSizeMin or 1.7,
        featuredSizeMax = config.featuredSizeMax or 2.6,
        tintMax = config.tintMax or 0.6,
        constellationCountMin = config.constellationCountMin or 3,
        constellationCountMax = config.constellationCountMax or 6,
        constellationStarsMin = config.constellationStarsMin or 6,
        constellationStarsMax = config.constellationStarsMax or 10,
        constellationLink = config.constellationLink or 120, -- typical distance between linked stars, design px
        constellationGap = config.constellationGap or 60, -- min clearance between two constellations
        constellationLoopChance = config.constellationLoopChance or 0.35,
        keepOut = config.keepOut or KEEP_OUT,
        lineAlpha = config.lineAlpha or 0.2,
        alpha = config.alpha or 1, -- global fade, on top of per-star twinkle brightness
        enabled = config.enabled ~= false,
    }, Stars)
end

--- featured stars are the constellations' own: larger and brighter than the
-- background, so they read as the figure's anchors
---@param x number
---@param y number
---@param featured? boolean
---@return table
function Stars:newStar(x, y, featured)
    local size, brightness
    if featured then
        size = Math.randRange(self.featuredSizeMin, self.featuredSizeMax)
        brightness = Math.randRange(0.85, 1.0)
    else
        local t = math.random() ^ 3 -- mostly small, the odd large one
        size = self.sizeMin + (self.sizeMax - self.sizeMin) * t
        brightness = Math.randRange(0.6, 0.85) + 0.15 * t
    end
    return {
        x = x,
        y = y,
        size = size,
        brightness = brightness,
        blinkPhase = Math.randAngle(),
        blinkSpeed = Math.randRange(self.blinkSpeedMin, self.blinkSpeedMax),
        tint = math.random(0, 1),
        tintAmount = self.tintMax * math.random() ^ 2, -- most near-white, a few clearly coloured
    }
end

---@return number # > 0 if c is left of a->b, < 0 if right, 0 if on it
local function orient(ax, ay, bx, by, cx, cy)
    return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
end

--- true only for a proper crossing: segments that merely share an endpoint
-- (two links meeting at a star) don't count
local function segmentsCross(ax, ay, bx, by, cx, cy, dx, dy)
    return orient(cx, cy, dx, dy, ax, ay) * orient(cx, cy, dx, dy, bx, by) < 0
        and orient(ax, ay, bx, by, cx, cy) * orient(ax, ay, bx, by, dx, dy) < 0
end

---@param x number
---@param y number
---@return boolean
function Stars:inKeepOut(x, y)
    for _, r in ipairs(self.keepOutPx) do
        if x > r[1] and x < r[3] and y > r[2] and y < r[4] then return true end
    end
    return false
end

--- a segment entering a rectangle with both ends outside it always crosses
-- one of its diagonals, so those two tests cover every case
---@return boolean
function Stars:lineInKeepOut(ax, ay, bx, by)
    if self:inKeepOut(ax, ay) or self:inKeepOut(bx, by) then return true end
    for _, r in ipairs(self.keepOutPx) do
        if segmentsCross(ax, ay, bx, by, r[1], r[2], r[3], r[4])
            or segmentsCross(ax, ay, bx, by, r[3], r[2], r[1], r[4]) then
            return true
        end
    end
    return false
end

---@param points table[] # { x, y }
---@param edges table[] # { i, j } into points
---@param i integer
---@param j integer
---@return boolean
function Stars:canLink(points, edges, i, j)
    local a, b = points[i], points[j]
    if self:lineInKeepOut(a.x, a.y, b.x, b.y) then return false end
    for _, e in ipairs(edges) do
        local c, d = points[e[1]], points[e[2]]
        if segmentsCross(a.x, a.y, b.x, b.y, c.x, c.y, d.x, d.y) then return false end
    end
    return true
end

---@return boolean
function Stars:clearOfConstellations(x, y, radius)
    for _, c in ipairs(self.constellations) do
        if Math.length(x - c.x, y - c.y) < radius + c.radius + self.constellationGap then return false end
    end
    return true
end

--- links along the tree between two stars; a loop only reads as a figure
-- (not a stray triangle) when it closes over three or more of them
---@param count integer
---@param edges table[]
---@param from integer
---@param to integer
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

--- scatters a cluster of stars in a tilted ellipse and links them with a
-- spanning tree -- shortest links first, capped per star, never crossing --
-- which branches the way star-chart figures do instead of snaking in a line.
-- Sometimes closes one loop. Stars and lines both stay out of keepOut.
---@param w number
---@param h number
function Stars:spawnConstellation(w, h)
    local count = Math.randInt(self.constellationStarsMin, self.constellationStarsMax)
    local link = self.constellationLink
    local radius = link * math.sqrt(count) * 0.6
    local mx, my = w * EDGE_MARGIN_X, h * EDGE_MARGIN_Y

    local cx, cy
    for _ = 1, PLACE_TRIES do
        local x, y = Math.randRange(mx, w - mx), Math.randRange(my, h - my)
        if not self:inKeepOut(x, y) and self:clearOfConstellations(x, y, radius) then
            cx, cy = x, y
            break
        end
    end
    if not cx then return end

    local tilt, aspect = Math.randAngle(), Math.randRange(0.45, 1)
    local cosT, sinT = math.cos(tilt), math.sin(tilt)
    local points = {}
    for _ = 1, count * 25 do
        if #points == count then break end
        local angle, dist = Math.randAngle(), radius * math.sqrt(math.random())
        local ox, oy = math.cos(angle) * dist, math.sin(angle) * dist * aspect
        local x, y = cx + ox * cosT - oy * sinT, cy + ox * sinT + oy * cosT
        local ok = x > mx and x < w - mx and y > my and y < h - my and not self:inKeepOut(x, y)
        for _, p in ipairs(points) do
            if not ok then break end
            ok = Math.length(x - p.x, y - p.y) >= link * MIN_SPACING
        end
        if ok then points[#points + 1] = { x = x, y = y } end
    end
    if #points < 4 then return end

    local inTree, degree, depth, edges = { [1] = true }, {}, { [1] = 0 }, {}
    for i = 1, #points do degree[i] = 0 end
    while true do
        local best, bi, bj = link * MAX_LINK, nil, nil
        for i = 1, #points do
            if inTree[i] and degree[i] < MAX_DEGREE then
                for j = 1, #points do
                    local d = Math.length(points[i].x - points[j].x, points[i].y - points[j].y)
                    if not inTree[j] and d < best and self:canLink(points, edges, i, j) then
                        best, bi, bj = d, i, j
                    end
                end
            end
        end
        if not bi then break end
        if bj == nil then break end -- all remaining stars are blocked by keepOut or existing links
        
        inTree[bj] = true
        degree[bi], degree[bj] = degree[bi] + 1, degree[bj] + 1
        depth[bj] = depth[bi] + 1
        edges[#edges + 1] = { bi, bj }
    end
    if #edges < 3 then return end

    if math.random() < self.constellationLoopChance then
        local best, bi, bj = link * MAX_LINK, nil, nil
        for i = 1, #points do
            for j = i + 1, #points do
                local d = Math.length(points[i].x - points[j].x, points[i].y - points[j].y)
                if inTree[i] and inTree[j] and d < best
                    and degree[i] < MAX_DEGREE and degree[j] < MAX_DEGREE
                    and treeHops(#points, edges, i, j) >= 3 and self:canLink(points, edges, i, j) then
                    best, bi, bj = d, i, j
                end
            end
        end
        if bi then
            -- grown from whichever end the trace reaches last, so it never
            -- starts from a star that hasn't been drawn to yet
            if depth[bi] < depth[bj] then bi, bj = bj, bi end
            edges[#edges + 1] = { bi, bj }
        end
    end

    for i, p in ipairs(points) do
        if inTree[i] then
            self.stars[#self.stars + 1] = self:newStar(p.x, p.y, true)
        end
    end
    local group = #self.constellations + 1
    for _, e in ipairs(edges) do
        local a, b = points[e[1]], points[e[2]]
        self.segments[#self.segments + 1] = { a.x, a.y, b.x, b.y, group = group, depth = depth[e[1]] }
    end
    self.constellations[group] = { x = cx, y = cy, radius = radius, glow = 0 }
end

---@param px number
---@param py number
---@param s table # a segment
---@return number
local function distanceToSegment(px, py, s)
    local dx, dy = s[3] - s[1], s[4] - s[2]
    local t = Math.clamp01(((px - s[1]) * dx + (py - s[2]) * dy) / (dx * dx + dy * dy))
    return Math.length(px - (s[1] + dx * t), py - (s[2] + dy * t))
end

--- where the cursor is, in screen space; nil when nothing points at the sky
-- (the cursor left the window, or a dialog is up over it)
---@param x number|nil
---@param y number|nil
function Stars:setPointer(x, y)
    if not x or not y then
        self.pointerX, self.pointerY = nil, nil
        return
    end
    local scale, ox, oy = Sky.cover(love.graphics.getDimensions())
    self.pointerX, self.pointerY = (x - ox) / scale, (y - oy) / scale
end

---@param segment table
---@return number # 0..1, how much of this line the intro trace has drawn
function Stars:traceProgress(segment)
    if Motion.reduced then return 1 end
    local start = TRACE_DELAY + (segment.group - 1) * TRACE_STAGGER + segment.depth * TRACE_LINK
    return Ease.outCubic(Math.clamp01((self.time - start) / TRACE_LINK))
end

--- regenerates the whole sky in Sky's fixed design space, never at the window
-- size: draw() scales it to cover the window, so a resize doesn't reshuffle it
function Stars:spawnStars()
    local w, h = Sky.W, Sky.H
    self.stars = {}
    self.segments = {}
    self.constellations = {}
    self.keepOutPx = {}
    for i, r in ipairs(self.keepOut) do
        self.keepOutPx[i] = { r[1] * w - KEEP_OUT_PAD, r[2] * h - KEEP_OUT_PAD,
                              r[3] * w + KEEP_OUT_PAD, r[4] * h + KEEP_OUT_PAD }
    end

    for _ = 1, Math.randInt(self.amountMin, self.amountMax) do
        self.stars[#self.stars + 1] = self:newStar(Math.randRange(0, w), Math.randRange(0, h))
    end

    for _ = 1, Math.randInt(self.constellationCountMin, self.constellationCountMax) do
        self:spawnConstellation(w, h)
    end

    self:buildBatches()
end

--- bakes every star into one static quad mesh, twinkle and tint parameters and all
function Stars:buildBatches()
    local vertices = {}
    for _, s in ipairs(self.stars) do
        local half = s.size / SPRITE_CORE
        for _, c in ipairs(QUAD_CORNERS) do
            vertices[#vertices + 1] = {
                s.x + c[1] * half, s.y + c[2] * half,
                (c[1] + 1) / 2, (c[2] + 1) / 2,
                s.brightness, s.blinkPhase, s.blinkSpeed,
                s.tint, s.tintAmount,
            }
        end
    end
    self.mesh = love.graphics.newMesh(STAR_VERTEX_FORMAT, vertices, "triangles", "static")
    self.mesh:setTexture(getSprite())
    getTwinkleShader()
end

--- advances the clock (the twinkle itself is the shader's job) and eases each
-- constellation's hover light toward whether the pointer is near its lines
---@param dt number
function Stars:update(dt)
    self.time = self.time + dt

    for _, c in ipairs(self.constellations) do c.lit = false end
    if self.pointerX then
        for _, s in ipairs(self.segments) do
            if distanceToSegment(self.pointerX, self.pointerY, s) < HOVER_REACH then
                self.constellations[s.group].lit = true
            end
        end
    end
    for _, c in ipairs(self.constellations) do
        c.glow = Math.damp(c.glow, c.lit and 1 or 0, HOVER_RATE, dt)
    end
end

--- constellation lines, then the whole sky in a single shaded draw
function Stars:draw()
    if not self.enabled or self.alpha <= 0 or not self.mesh then return end

    local scale, x, y = Sky.cover(love.graphics.getDimensions())
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.scale(scale)

    local prevWidth = love.graphics.getLineWidth()
    love.graphics.setLineWidth(1 / scale) -- line width scales with the transform; keep it one screen pixel
    for _, s in ipairs(self.segments) do
        local t = self:traceProgress(s)
        if t > 0 then
            local glow = self.constellations[s.group].glow
            local r, g, b = Theme.lerp(Theme.colors.textDim, Theme.colors.accentBright, glow)
            love.graphics.setColor(r, g, b, (self.lineAlpha + (HOVER_ALPHA - self.lineAlpha) * glow) * self.alpha)
            love.graphics.line(s[1], s[2], s[1] + (s[3] - s[1]) * t, s[2] + (s[4] - s[2]) * t)
        end
    end
    love.graphics.setLineWidth(prevWidth)

    local oscillation = Motion.reduced and 0 or self.brightnessOscillation -- reduced motion: no twinkle
    local shader = getTwinkleShader()
    shader:send("time", self.time)
    shader:send("oscillation", oscillation)
    shader:send("tintA", normalized(Theme.colors.accent))
    shader:send("tintB", normalized(Theme.colors.accentAlt))

    Theme.setColor(Theme.colors.star, self.alpha)
    love.graphics.setShader(shader)
    love.graphics.draw(self.mesh)
    love.graphics.setShader()
    love.graphics.pop()
end

return Stars
