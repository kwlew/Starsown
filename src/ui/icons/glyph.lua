-- Small procedural icons, drawn from primitives inside a 0..1 unit box
-- scaled to whatever size the caller asks for. No image assets, same reason
-- githubMark draws from a path: crisp at every UI scale, free to ship, and recolor with the theme.
--
--   Theme.setColor(Theme.colors.accent)
--   Glyph.draw("tower", x, y, 48)
--
-- Everything draws in the *current* color, so tinting is the caller's job.

local Glyph = {}

local STROKE = 0.075 -- stroke weight as a fraction of size, so 24px and 72px read as the same weight

local CIRCLE_SEGMENTS = 32 -- explicit: LÖVE's default picks too few at these radii

-- scratch for point-list glyphs, reused rather than reallocated per call
-- (polygon() has copied its args by the time it returns)
local scratch = {}

local function poly(mode, x, y, s, unit)
    local n = #unit
    for i = 1, n, 2 do
        scratch[i]     = x + unit[i] * s
        scratch[i + 1] = y + unit[i + 1] * s
    end
    love.graphics.polygon(mode, unpack(scratch, 1, n))
end

local function circle(mode, x, y, s, cx, cy, r)
    love.graphics.circle(mode, x + cx * s, y + cy * s, r * s, CIRCLE_SEGMENTS)
end

local function line(x, y, s, x1, y1, x2, y2)
    love.graphics.line(x + x1 * s, y + y1 * s, x + x2 * s, y + y2 * s)
end

local function box(mode, x, y, s, x1, y1, x2, y2, radius)
    love.graphics.rectangle(mode, x + x1 * s, y + y1 * s,
        (x2 - x1) * s, (y2 - y1) * s, (radius or 0) * s, (radius or 0) * s)
end

-- five-pointed star, built once at load
local STAR = {}
do
    for i = 0, 9 do
        local angle = -math.pi / 2 + i * math.pi / 5
        local r = (i % 2 == 0) and 0.48 or 0.20
        STAR[#STAR + 1] = 0.5 + math.cos(angle) * r
        STAR[#STAR + 1] = 0.5 + math.sin(angle) * r
    end
end

local SHIELD = { 0.50, 0.06, 0.88, 0.22, 0.88, 0.50, 0.50, 0.94, 0.12, 0.50, 0.12, 0.22 }
local FLAME  = { 0.50, 0.04, 0.72, 0.30, 0.63, 0.43, 0.80, 0.63, 0.62, 0.94,
                 0.38, 0.94, 0.20, 0.63, 0.37, 0.43, 0.28, 0.30 }
local TOWER_BASE = { 0.20, 0.94, 0.80, 0.94, 0.70, 0.74, 0.30, 0.74 }
local CUP = { 0.26, 0.10, 0.74, 0.10, 0.66, 0.52, 0.34, 0.52 }

-- each glyph draws inside (x, y) .. (x+size, y+size); caller owns the color
local glyphs = {}

function glyphs.tower(x, y, s)
    poly("fill", x, y, s, TOWER_BASE)
    box("fill", x, y, s, 0.38, 0.42, 0.62, 0.76)
    circle("fill", x, y, s, 0.5, 0.38, 0.17)
    box("fill", x, y, s, 0.44, 0.06, 0.56, 0.38)
end

function glyphs.wave(x, y, s)
    for _, r in ipairs({ 0.20, 0.33, 0.46 }) do
        love.graphics.arc("line", "open", x + 0.22 * s, y + 0.5 * s, r * s, -0.85, 0.85, 16)
    end
    circle("fill", x, y, s, 0.22, 0.5, 0.07)
end

function glyphs.shield(x, y, s)
    poly("line", x, y, s, SHIELD)
    line(x, y, s, 0.50, 0.30, 0.50, 0.70)
    line(x, y, s, 0.32, 0.45, 0.68, 0.45)
end

function glyphs.coin(x, y, s)
    circle("line", x, y, s, 0.5, 0.5, 0.38)
    box("fill", x, y, s, 0.45, 0.20, 0.55, 0.80)
    line(x, y, s, 0.34, 0.34, 0.66, 0.34)
    line(x, y, s, 0.34, 0.66, 0.66, 0.66)
end

function glyphs.gear(x, y, s)
    circle("line", x, y, s, 0.5, 0.5, 0.30)
    circle("fill", x, y, s, 0.5, 0.5, 0.11)
    for i = 0, 7 do
        local a = i * math.pi / 4
        local c, sn = math.cos(a), math.sin(a)
        line(x, y, s, 0.5 + c * 0.30, 0.5 + sn * 0.30, 0.5 + c * 0.46, 0.5 + sn * 0.46)
    end
end

function glyphs.crosshair(x, y, s)
    circle("line", x, y, s, 0.5, 0.5, 0.28)
    circle("fill", x, y, s, 0.5, 0.5, 0.07)
    line(x, y, s, 0.5, 0.02, 0.5, 0.20)
    line(x, y, s, 0.5, 0.80, 0.5, 0.98)
    line(x, y, s, 0.02, 0.5, 0.20, 0.5)
    line(x, y, s, 0.80, 0.5, 0.98, 0.5)
end

function glyphs.star(x, y, s)
    poly("fill", x, y, s, STAR)
end

function glyphs.flame(x, y, s)
    poly("fill", x, y, s, FLAME)
end

function glyphs.frost(x, y, s)
    for i = 0, 2 do
        local a = i * math.pi / 3
        local c, sn = math.cos(a), math.sin(a)
        line(x, y, s, 0.5 - c * 0.44, 0.5 - sn * 0.44, 0.5 + c * 0.44, 0.5 + sn * 0.44)
        for _, dir in ipairs({ 1, -1 }) do -- barbs near each tip, angled off the spoke
            local tipX, tipY = 0.5 + c * 0.44 * dir, 0.5 + sn * 0.44 * dir
            local b = a + math.pi / 3
            line(x, y, s, tipX, tipY,
                tipX - math.cos(b) * 0.16 * dir, tipY - math.sin(b) * 0.16 * dir)
        end
    end
end

function glyphs.trophy(x, y, s)
    poly("fill", x, y, s, CUP)
    box("fill", x, y, s, 0.44, 0.52, 0.56, 0.74)
    box("fill", x, y, s, 0.28, 0.74, 0.72, 0.88, 0.03)
    love.graphics.arc("line", "open", x + 0.26 * s, y + 0.24 * s, 0.14 * s, -1.4, 1.4, 12)
    love.graphics.arc("line", "open", x + 0.74 * s, y + 0.24 * s, 0.14 * s, 1.74, 4.54, 12)
end

function glyphs.clock(x, y, s)
    circle("line", x, y, s, 0.5, 0.5, 0.40)
    line(x, y, s, 0.5, 0.5, 0.5, 0.24)
    line(x, y, s, 0.5, 0.5, 0.70, 0.60)
end

function glyphs.lock(x, y, s)
    love.graphics.arc("line", "open", x + 0.5 * s, y + 0.44 * s, 0.20 * s, math.pi, 2 * math.pi, 16)
    box("fill", x, y, s, 0.24, 0.44, 0.76, 0.90, 0.06)
end

-- unknown name falls back to the lock instead of throwing: an unfinished icon should look unfinished, not crash
function Glyph.draw(name, x, y, size)
    local draw = glyphs[name] or glyphs.lock
    local previous = love.graphics.getLineWidth()
    love.graphics.setLineWidth(math.max(1, size * STROKE))
    draw(x, y, size)
    love.graphics.setLineWidth(previous)
end

function Glyph.has(name)
    return glyphs[name] ~= nil
end

return Glyph
