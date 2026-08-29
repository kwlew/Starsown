-- Renders a single-path SVG icon (square viewBox, e.g. 24x24) straight from
-- its path string, no image asset -- flattened to a triangle-fan mesh once,
-- then filled with an even-odd stencil each draw. Robust for concave
-- silhouettes (unlike love.graphics.polygon, whose ear-clipping can throw on
-- near-collinear bezier points).
--
-- One instance per glyph, so two icons never share (or evict) each other's
-- cache -- see ui/icons/marks.lua, which wraps a whole table of these:
--
--   local mark = SvgIcon.new(PATH, 24)
--   mark:draw(x, y, size, color, glow)
--
-- Path commands supported: M/m, L/l, C/c, A/a (elliptical arc), Z/z --
-- covers every glyph fed to it so far; add a case to flatten() for anything else.

local Math = require "utils.math"

local SvgIcon = {}
SvgIcon.__index = SvgIcon

local GLOW_LAYERS = 4
local GLOW_SPREAD = 0.09
local GLOW_ALPHA = 0.30

local MAX_CACHED = 8

local function tokenize(d)
    local tokens, i, n = {}, 1, #d
    local cmd, argIndex = nil, 0
    while i <= n do
        local c = d:sub(i, i)
        if c:match("%a") then
            cmd, argIndex = c, 0
            tokens[#tokens + 1] = { cmd = c }
            i = i + 1
        elseif c:match("%s") or c == "," then
            i = i + 1
        else
            local isFlag = (cmd == "a" or cmd == "A")
                and (argIndex % 7 == 3 or argIndex % 7 == 4)
            local j = i
            if isFlag then
                j = i + 1
            else
                if d:sub(j, j):match("[%+%-]") then j = j + 1 end
                while j <= n and d:sub(j, j):match("%d") do j = j + 1 end
                if d:sub(j, j) == "." then
                    j = j + 1
                    while j <= n and d:sub(j, j):match("%d") do j = j + 1 end
                end
            end
            tokens[#tokens + 1] = { num = tonumber(d:sub(i, j - 1)) }
            argIndex = argIndex + 1
            i = j
        end
    end
    return tokens
end

-- endpoint-to-center parameterization
local function arcPoints(x0, y0, rx, ry, rotDeg, largeArc, sweep, x, y, steps)
    rx, ry = math.abs(rx), math.abs(ry)
    if rx == 0 or ry == 0 or (x0 == x and y0 == y) then
        return { x, y } -- degenerate arc: SVG treats it as a straight line
    end

    local phi = math.rad(rotDeg)
    local cosPhi, sinPhi = math.cos(phi), math.sin(phi)

    local dx2, dy2 = (x0 - x) / 2, (y0 - y) / 2
    local x1p = cosPhi * dx2 + sinPhi * dy2
    local y1p = -sinPhi * dx2 + cosPhi * dy2

    local rxSq, rySq = rx * rx, ry * ry
    local x1pSq, y1pSq = x1p * x1p, y1p * y1p
    local lambda = x1pSq / rxSq + y1pSq / rySq
    if lambda > 1 then
        local s = math.sqrt(lambda)
        rx, ry = rx * s, ry * s
        rxSq, rySq = rx * rx, ry * ry
    end

    local sign = (largeArc ~= sweep) and 1 or -1
    local num = rxSq * rySq - rxSq * y1pSq - rySq * x1pSq
    local den = rxSq * y1pSq + rySq * x1pSq
    local co = (den > 0 and num > 0) and sign * math.sqrt(num / den) or 0
    local cxp = co * (rx * y1p / ry)
    local cyp = co * (-ry * x1p / rx)

    local cx = cosPhi * cxp - sinPhi * cyp + (x0 + x) / 2
    local cy = sinPhi * cxp + cosPhi * cyp + (y0 + y) / 2

    -- signed angle from (ux,uy) to (vx,vy): cross product for sign, dot
    -- product (clamped against float drift) for magnitude
    local function angleBetween(ux, uy, vx, vy)
        local dot = ux * vx + uy * vy
        local len = math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
        local a = math.acos(Math.clamp(dot / len, -1, 1))
        if ux * vy - uy * vx < 0 then a = -a end
        return a
    end

    local ux, uy = (x1p - cxp) / rx, (y1p - cyp) / ry
    local vx, vy = (-x1p - cxp) / rx, (-y1p - cyp) / ry

    local theta1 = angleBetween(1, 0, ux, uy)
    local dtheta = angleBetween(ux, uy, vx, vy)
    if not sweep and dtheta > 0 then dtheta = dtheta - 2 * math.pi end
    if sweep and dtheta < 0 then dtheta = dtheta + 2 * math.pi end

    local pts = {}
    for s = 1, steps do
        local t = theta1 + dtheta * (s / steps)
        local ct, st = math.cos(t), math.sin(t)
        pts[#pts + 1] = cx + rx * cosPhi * ct - ry * sinPhi * st
        pts[#pts + 1] = cy + rx * sinPhi * ct + ry * cosPhi * st
    end
    return pts
end

local function flatten(d, svgSize, steps)
    local tokens = tokenize(d)
    local pts, idx = {}, 1
    local subpaths, subpathPoints = {}, 0
    local function num() local t = tokens[idx]; idx = idx + 1; return t.num end

    local cx, cy, sx, sy, cmd = 0, 0, 0, 0, nil
    local function add(x, y)
        pts[#pts + 1] = x / svgSize
        pts[#pts + 1] = y / svgSize
        subpathPoints = subpathPoints + 1
    end

    local function startSubpath()
        if subpathPoints > 0 then subpaths[#subpaths + 1] = subpathPoints end
        subpathPoints = 0
    end
    local function cubic(x1, y1, x2, y2, x3, y3)
        local x0, y0 = cx, cy
        for s = 1, steps do
            local t = s / steps
            local mt = 1 - t
            add(mt * mt * mt * x0 + 3 * mt * mt * t * x1 + 3 * mt * t * t * x2 + t * t * t * x3,
                mt * mt * mt * y0 + 3 * mt * mt * t * y1 + 3 * mt * t * t * y2 + t * t * t * y3)
        end
        cx, cy = x3, y3
    end
    local function arc(rx, ry, rotDeg, largeArc, sweep, ex, ey)
        local raw = arcPoints(cx, cy, rx, ry, rotDeg, largeArc, sweep, ex, ey, steps)
        for i = 1, #raw, 2 do add(raw[i], raw[i + 1]) end
        cx, cy = ex, ey
    end

    while idx <= #tokens do
        if tokens[idx].cmd then cmd = tokens[idx].cmd; idx = idx + 1 end
        if cmd == "M" then
            startSubpath()
            cx, cy = num(), num(); sx, sy = cx, cy; add(cx, cy); cmd = "L"
        elseif cmd == "m" then
            startSubpath()
            cx, cy = cx + num(), cy + num(); sx, sy = cx, cy; add(cx, cy); cmd = "l"
        elseif cmd == "L" then
            cx, cy = num(), num(); add(cx, cy)
        elseif cmd == "l" then
            cx, cy = cx + num(), cy + num(); add(cx, cy)
        elseif cmd == "C" then
            cubic(num(), num(), num(), num(), num(), num())
        elseif cmd == "c" then
            cubic(cx + num(), cy + num(), cx + num(), cy + num(), cx + num(), cy + num())
        elseif cmd == "A" then
            arc(num(), num(), num(), num() ~= 0, num() ~= 0, num(), num())
        elseif cmd == "a" then
            local rx, ry, rot = num(), num(), num()
            local largeArc, sweep = num() ~= 0, num() ~= 0
            arc(rx, ry, rot, largeArc, sweep, cx + num(), cy + num())
        elseif cmd == "z" or cmd == "Z" then
            cx, cy = sx, sy
        else
            error("svgIcon: unsupported path command '" .. tostring(cmd) .. "'")
        end
    end
    startSubpath() -- flush whatever subpath the loop ended mid-way through
    return pts, subpaths
end


function SvgIcon.new(path, svgSize, glow)
    glow = glow or {}
    local points, subpaths = flatten(path, svgSize, 10)
    return setmetatable({
        points = points,
        subpaths = subpaths,
        mesh = nil, -- built lazily, on first draw (see fillMark)
        glowLayers = glow.layers or GLOW_LAYERS,
        glowSpread = glow.spread or GLOW_SPREAD,
        glowAlpha = glow.alpha or GLOW_ALPHA,
        cache = {}, cacheCount = 0,
    }, SvgIcon)
end

function SvgIcon:buildMesh()
    local verts = {}
    local base = 1 -- flat index (1-based) of the current subpath's first point
    for _, count in ipairs(self.subpaths) do
        local firstX, firstY = self.points[base], self.points[base + 1]
        for k = 1, count - 2 do
            verts[#verts + 1] = { firstX, firstY }
            verts[#verts + 1] = { self.points[base + k * 2], self.points[base + k * 2 + 1] }
            verts[#verts + 1] = { self.points[base + (k + 1) * 2], self.points[base + (k + 1) * 2 + 1] }
        end
        base = base + count * 2
    end
    return love.graphics.newMesh(verts, "triangles")
end

function SvgIcon:fillMark(x, y, size)
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

function SvgIcon:paint(x, y, size, color, glowAmount)
    if glowAmount > 0 then
        love.graphics.setBlendMode("add")
        for i = self.glowLayers, 1, -1 do
            local grow = i * size * self.glowSpread
            love.graphics.setColor(color[1], color[2], color[3], self.glowAlpha * glowAmount / i)
            self:fillMark(x - grow / 2, y - grow / 2, size + grow)
        end
        love.graphics.setBlendMode("alpha")
    end

    love.graphics.setColor(color)
    self:fillMark(x, y, size)
end

function SvgIcon:render(size, color, glowAmount)

    local pad = math.ceil(size * self.glowLayers * self.glowSpread / 2) + 1
    local canvas = love.graphics.newCanvas(size + pad * 2, size + pad * 2)

    local previousCanvas = love.graphics.getCanvas()
    local r, g, b, a = love.graphics.getColor()

    love.graphics.setCanvas({ canvas, stencil = true })
    love.graphics.clear(0, 0, 0, 0)
    self:paint(pad, pad, size, color, glowAmount)
    love.graphics.setCanvas(previousCanvas)

    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(r, g, b, a)
    return { canvas = canvas, pad = pad }
end

function SvgIcon:draw(x, y, size, color, glowAmount)
    glowAmount = glowAmount or 0
    size = Math.round(size) -- integral, so the cache key is stable

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

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode("alpha", "premultiplied")
    love.graphics.draw(entry.canvas, x - entry.pad, y - entry.pad)
    love.graphics.setBlendMode("alpha")
end

return SvgIcon
