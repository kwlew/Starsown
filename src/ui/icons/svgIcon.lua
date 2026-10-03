--- Draws a single-path SVG mark (square viewBox, e.g. 24x24) from its path
-- string, no image asset: flattened once by SvgPath, turned into a
-- triangle-fan mesh, filled through an even-odd stencil so concave shapes
-- and holes come out right, and baked per size/colour/glow to a canvas.
--
--   local mark = SvgIcon.new(PATH, 24)
--   mark:draw(x, y, size, color, glow)
--
-- One instance per mark, so two marks never share (or evict) each other's
-- cache -- see Marks, which wraps a whole table of these.

local Math = require("utils.math")
local SvgPath = require("ui.icons.svgPath")

local SvgIcon = {}
SvgIcon.__index = SvgIcon

local CURVE_STEPS = 10
local GLOW_LAYERS = 4
local GLOW_SPREAD = 0.09
local GLOW_ALPHA = 0.30

local MAX_CACHED = 8

--- flattens the path to points once; the mesh itself waits for the first draw
---@param path string # an SVG path's `d` attribute, single path only
---@param svgSize number # the viewBox edge, e.g. 24
---@param glow? table # { layers?: integer, spread?: number, alpha?: number }
---@return table
function SvgIcon.new(path, svgSize, glow)
    glow = glow or {}
    local points, subpaths = SvgPath.flatten(path, svgSize, CURVE_STEPS)
    return setmetatable({
        points = points,
        subpaths = subpaths,
        mesh = nil,
        glowLayers = glow.layers or GLOW_LAYERS,
        glowSpread = glow.spread or GLOW_SPREAD,
        glowAlpha = glow.alpha or GLOW_ALPHA,
        cache = {}, cacheCount = 0,
    }, SvgIcon)
end

--- a triangle fan per subpath. Overlapping fans are fine: the even-odd
-- stencil is what turns them back into an outline with holes.
---@return any # a love.Mesh
function SvgIcon:buildMesh()
    local verts = {}
    local points = self.points
    local base = 1 -- flat index (1-based) of the current subpath's first point
    for _, count in ipairs(self.subpaths) do
        local firstX, firstY = points[base], points[base + 1]
        for k = 1, count - 2 do
            verts[#verts + 1] = { firstX, firstY }
            verts[#verts + 1] = { points[base + k * 2], points[base + k * 2 + 1] }
            verts[#verts + 1] = { points[base + (k + 1) * 2], points[base + (k + 1) * 2 + 1] }
        end
        base = base + count * 2
    end
    return love.graphics.newMesh(verts, "triangles")
end

--- fills the silhouette in the current colour
---@param x number
---@param y number
---@param size number
function SvgIcon:fill(x, y, size)
    self.mesh = self.mesh or self:buildMesh()

    love.graphics.stencil(function()
        love.graphics.push()
        love.graphics.translate(x, y)
        love.graphics.scale(size, size)
        love.graphics.draw(self.mesh)
        love.graphics.pop()
    end, "invert", 1)

    love.graphics.setStencilTest("notequal", 0)
    love.graphics.rectangle("fill", x, y, size, size)
    love.graphics.setStencilTest()
end

--- the mark, under an additive bloom of progressively larger copies
---@param x number
---@param y number
---@param size number
---@param color number[]
---@param glowAmount number # 0..1
function SvgIcon:paint(x, y, size, color, glowAmount)
    if glowAmount > 0 then
        love.graphics.setBlendMode("add")
        for i = self.glowLayers, 1, -1 do
            local grow = i * size * self.glowSpread
            love.graphics.setColor(color[1], color[2], color[3], self.glowAlpha * glowAmount / i)
            self:fill(x - grow / 2, y - grow / 2, size + grow)
        end
        love.graphics.setBlendMode("alpha")
    end

    love.graphics.setColor(color[1], color[2], color[3], 1)
    self:fill(x, y, size)
end

--- bakes one size/colour/glow variant to its own canvas, padded for the
-- bloom, handing back every bit of graphics state it borrowed
---@param size number
---@param color number[]
---@param glowAmount number
---@return table # { canvas: love.Canvas, pad: number }
function SvgIcon:render(size, color, glowAmount)
    local pad = math.ceil(size * self.glowLayers * self.glowSpread / 2) + 1
    local canvas = love.graphics.newCanvas(size + pad * 2, size + pad * 2)

    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setCanvas({ canvas, stencil = true })
    love.graphics.clear(0, 0, 0, 0)
    self:paint(pad, pad, size, color, glowAmount)
    love.graphics.pop()
    return { canvas = canvas, pad = pad }
end

--- draws from a per-variant canvas cache, so a hover's changing glow costs one
-- bake per distinct value rather than a stencil pass per frame
---@param x number
---@param y number
---@param size number # rounded, to keep cache keys stable
---@param color number[]
---@param glowAmount? number # 0..1, defaults to 0
function SvgIcon:draw(x, y, size, color, glowAmount)
    glowAmount = glowAmount or 0
    size = Math.round(size)

    local key = string.format("%d|%.3f,%.3f,%.3f|%.3f",
        size, color[1], color[2], color[3], glowAmount)

    local entry = self.cache[key]
    if not entry then
        if self.cacheCount >= MAX_CACHED then
            self.cache, self.cacheCount = {}, 0 -- release variants from older UI scales
        end
        entry = self:render(size, color, glowAmount)
        self.cache[key] = entry
        self.cacheCount = self.cacheCount + 1
    end

    love.graphics.push("all")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode("alpha", "premultiplied")
    love.graphics.draw(entry.canvas, x - entry.pad, y - entry.pad)
    love.graphics.pop()
end

return SvgIcon
