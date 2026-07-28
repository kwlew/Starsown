-- lib/ui/githubMark.lua
-- The official GitHub mark, rendered straight from its SVG path (viewBox 24x24)
-- so it needs no image asset and stays crisp at any size. The path is flattened
-- to a polygon once, then filled with an even-odd stencil each draw — robust for
-- the concave silhouette (unlike love.graphics.polygon, whose ear-clipping can
-- throw on near-collinear bezier points).

local GithubMark = {}

-- Halo tuning: how many stamps, how far each grows (as a fraction of the mark's
-- size), and the per-layer alpha. Mirrors Theme.metrics' glow* values, but in
-- glyph-relative units so the halo scales with the icon.
local GLOW_LAYERS = 4
local GLOW_SPREAD = 0.09
local GLOW_ALPHA = 0.30

local SVG_SIZE = 24
local PATH = "M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12"

-- Splits an SVG path into an ordered stream of command letters and numbers.
-- Numbers are scanned by hand (not %S+) because SVG packs them tightly, e.g.
-- ".6.113" is two numbers and "0-12" is two numbers.
local function tokenize(d)
    local tokens, i, n = {}, 1, #d
    while i <= n do
        local c = d:sub(i, i)
        if c:match("%a") then
            tokens[#tokens + 1] = { cmd = c }
            i = i + 1
        elseif c:match("%s") or c == "," then
            i = i + 1
        else
            local j = i
            if d:sub(j, j):match("[%+%-]") then j = j + 1 end
            while j <= n and d:sub(j, j):match("%d") do j = j + 1 end
            if d:sub(j, j) == "." then
                j = j + 1
                while j <= n and d:sub(j, j):match("%d") do j = j + 1 end
            end
            tokens[#tokens + 1] = { num = tonumber(d:sub(i, j - 1)) }
            i = j
        end
    end
    return tokens
end

-- Flattens the path (supporting the M/L/C commands it uses, absolute and
-- relative) into a flat {x1, y1, x2, y2, ...} list normalized to a 0..1 box.
local function flatten(d, steps)
    local tokens = tokenize(d)
    local pts, idx = {}, 1
    local function num() local t = tokens[idx]; idx = idx + 1; return t.num end

    local cx, cy, sx, sy, cmd = 0, 0, 0, 0, nil
    local function add(x, y) pts[#pts + 1] = x / SVG_SIZE; pts[#pts + 1] = y / SVG_SIZE end
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

    while idx <= #tokens do
        if tokens[idx].cmd then cmd = tokens[idx].cmd; idx = idx + 1 end
        if cmd == "M" then
            cx, cy = num(), num(); sx, sy = cx, cy; add(cx, cy); cmd = "L"
        elseif cmd == "m" then
            cx, cy = cx + num(), cy + num(); sx, sy = cx, cy; add(cx, cy); cmd = "l"
        elseif cmd == "L" then
            cx, cy = num(), num(); add(cx, cy)
        elseif cmd == "l" then
            cx, cy = cx + num(), cy + num(); add(cx, cy)
        elseif cmd == "C" then
            cubic(num(), num(), num(), num(), num(), num())
        elseif cmd == "c" then
            cubic(cx + num(), cy + num(), cx + num(), cy + num(), cx + num(), cy + num())
        elseif cmd == "z" or cmd == "Z" then
            cx, cy = sx, sy
        else
            error("githubMark: unsupported path command '" .. tostring(cmd) .. "'")
        end
    end
    return pts
end

local UNIT_POINTS = flatten(PATH, 10)

-- Fan mesh over the outline, built once in the 0..1 box. Drawn under a
-- translate/scale so the same mesh serves every size. As a triangle fan its
-- triangles overlap outside the silhouette, but the even-odd stencil below only
-- keeps pixels covered an odd number of times — i.e. the true interior.
local mesh

local function buildMesh()
    local verts = {}
    for i = 1, #UNIT_POINTS, 2 do
        verts[#verts + 1] = { UNIT_POINTS[i], UNIT_POINTS[i + 1] }
    end
    return love.graphics.newMesh(verts, "fan")
end

-- Fills the silhouette in the square at (x, y) with the current draw color.
-- The "invert" stencil action flips each covered pixel's bits, so the fan's
-- overlapping triangles cancel outside the glyph and only the true interior is
-- left odd. Note the test must be "notequal 0", NOT "equal 1": a bitwise invert
-- turns 0 into 255, so comparing against 1 would match nothing at all.
local function fillMark(x, y, size)
    mesh = mesh or buildMesh()

    love.graphics.stencil(function()
        love.graphics.push()
        love.graphics.translate(x, y)
        love.graphics.scale(size, size)
        love.graphics.draw(mesh)
        love.graphics.pop()
    end, "invert", 1)

    love.graphics.setStencilTest("notequal", 0)
    love.graphics.rectangle("fill", x, y, size, size)
    love.graphics.setStencilTest()
end

-- Paints the mark and its halo into the current target, glyph top-left at
-- (x, y). Every stamp is a stencil round-trip, which is why the result is
-- cached rather than run per frame (see GithubMark.draw).
local function paint(x, y, size, color, glow)
    if glow > 0 then
        -- Glyph-shaped halo: the same silhouette stamped a few times at
        -- increasing size, additively, so the glow hugs the logo's outline
        -- instead of sitting behind it as a square blob.
        love.graphics.setBlendMode("add")
        for i = GLOW_LAYERS, 1, -1 do
            local grow = i * size * GLOW_SPREAD
            love.graphics.setColor(color[1], color[2], color[3], GLOW_ALPHA * glow / i)
            fillMark(x - grow / 2, y - grow / 2, size + grow)
        end
        love.graphics.setBlendMode("alpha")
    end

    love.graphics.setColor(color)
    fillMark(x, y, size)
end

-- Rendered variants, keyed by size + colour + glow. The mark is static art, so
-- the five stencil passes that build it only need to run when one of those
-- changes — not every frame, forever, for a 26px icon. The menu uses two
-- variants (idle and hovered); a UI rescale introduces one more pair, and the
-- cache is wiped rather than evicted once a few sizes have accumulated.
local MAX_CACHED = 8
local cache, cacheCount = {}, 0

local function render(size, color, glow)
    -- The halo reaches beyond the glyph box, so the canvas carries padding for
    -- it: the outermost stamp grows by GLOW_LAYERS * size * GLOW_SPREAD, half
    -- of that on each side.
    local pad = math.ceil(size * GLOW_LAYERS * GLOW_SPREAD / 2) + 1
    local canvas = love.graphics.newCanvas(size + pad * 2, size + pad * 2)

    local previousCanvas = love.graphics.getCanvas()
    local r, g, b, a = love.graphics.getColor()

    -- stencil = true: fillMark needs a stencil buffer on the target.
    love.graphics.setCanvas({ canvas, stencil = true })
    love.graphics.clear(0, 0, 0, 0)
    paint(pad, pad, size, color, glow)
    love.graphics.setCanvas(previousCanvas)

    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(r, g, b, a)
    return { canvas = canvas, pad = pad }
end

-- Draws the mark filling the square at (x, y) with side `size`, in `color`
-- ({r, g, b} or {r, g, b, a}). `glow` (0..1, default 0) adds a soft additive
-- halo in the same shape as the glyph, so the mark stays legible against a
-- busy background. Restores draw color and blend mode after.
function GithubMark.draw(x, y, size, color, glow)
    glow = glow or 0
    size = math.floor(size + 0.5) -- integral, so the cache key is stable

    local key = string.format("%d|%.3f,%.3f,%.3f|%.3f",
        size, color[1], color[2], color[3], glow)

    local entry = cache[key]
    if not entry then
        if cacheCount >= MAX_CACHED then
            cache, cacheCount = {}, 0 -- release variants from older UI scales
        end
        entry = render(size, color, glow)
        cache[key] = entry
        cacheCount = cacheCount + 1
    end

    -- Premultiplied: the canvas already composited the halo against its own
    -- alpha, so blending it again as straight alpha would darken those edges.
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode("alpha", "premultiplied")
    love.graphics.draw(entry.canvas, x - entry.pad, y - entry.pad)
    love.graphics.setBlendMode("alpha")
end

return GithubMark
