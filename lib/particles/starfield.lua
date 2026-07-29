-- lib/particles/starfield.lua
-- Shooting stars that streak across the menu sky and can be clicked to pop.
-- TODO: meteor shower mode (a faster spawn profile).

local Theme = require "lib.ui.theme"
local Math = require "lib.utils.math"
local Burst = require "lib.particles.burst"
local Audio = require "lib.audio"
local Audios = require "lib.utils.audios"

-- Star palette: in-flight colour, then the flare it ages into.
local WHITE       = { 1, 1, 1 }
local WHITE_FLARE = { 1, 0.2, 0.15 }

local GOLD        = { 1, 0.82, 0.35 }
local GOLD_FLARE  = { 1, 0.6, 0.12 }

local Starfield = {}
Starfield.__index = Starfield

function Starfield.new(config)
    config = config or {}
    return setmetatable({
        stars = {},
        burst = Burst.new(config.burst),
        -- How far from a star's center a click still counts as a hit.
        clickRadius = config.clickRadius or 20,
        timer = 0,
        spawnMin = config.spawnMin or 0.8,
        spawnMax = config.spawnMax or 1.3,
        speedMin = config.speedMin or 100,
        speedMax = config.speedMax or 450,
        lengthMin = config.lengthMin or 120,
        lengthMax = config.lengthMax or 500,
        lifeMin = config.lifeMin or 1.5,
        lifeMax = config.lifeMax or 5.2,
        dyingThreshold = config.dyingThreshold or 0.5,
        -- Rare golden stars: slower and longer-lived, so they linger long enough
        -- to be noticed and clicked.
        goldenChance = config.goldenChance or 0.003,
        goldenSpeedMin = config.goldenSpeedMin or 70,
        goldenSpeedMax = config.goldenSpeedMax or 110,
        goldenLifeMin = config.goldenLifeMin or 9,
        goldenLifeMax = config.goldenLifeMax or 13,
    }, Starfield)
end

function Starfield:spawnStar()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()

    local golden = math.random() < self.goldenChance
    local speedMin, speedMax = self.speedMin, self.speedMax
    local lifeMin, lifeMax = self.lifeMin, self.lifeMax
    if golden then
        speedMin, speedMax = self.goldenSpeedMin, self.goldenSpeedMax
        lifeMin, lifeMax = self.goldenLifeMin, self.goldenLifeMax
    end

    local x = Math.randRange(-0.05 * w, 0.65 * w)
    local y = Math.randRange(-0.05 * h, 0.03 * h)
    local angle = math.rad(Math.randRange(42, 48))
    local speed = Math.randRange(speedMin, speedMax)
    self.stars[#self.stars + 1] = {
        x = x, y = y,
        spawnX = x, spawnY = y, -- fixed origin, so the trail can grow from here
        vx = math.cos(angle) * speed,
        vy = math.sin(angle) * speed,
        length = Math.randRange(self.lengthMin, self.lengthMax),
        life = 0,
        maxLife = Math.randRange(lifeMin, lifeMax),
        golden = golden,
        color = golden and GOLD or WHITE,
        flare = golden and GOLD_FLARE or WHITE_FLARE,
        -- Golden stars are drawn a little heavier so they register as special
        -- from the corner of the eye, before the colour is even read.
        scale = golden and 1.7 or 1,
    }
end

local function dyingFactor(s, threshold)
    local lifeRatio = s.life / s.maxLife
    if lifeRatio <= threshold then return 0 end
    return (lifeRatio - threshold) / (1 - threshold)
end

-- How long a clicked star's orphaned trail hangs in the air, dissolving, after
-- the burst has taken its head. `s.popped` counts seconds into that.
local POP_FADE = 0.7

-- Slack around the window before a star counts as gone, so nothing is culled
-- while any part of its halo could still be showing.
local CULL_MARGIN = 64

local function fullyOffScreen(s)
    local w, h = love.graphics.getDimensions()
    local speed = Math.length(s.vx, s.vy)
    if speed == 0 then return false end

    local length = math.min(s.length, Math.length(s.x - s.spawnX, s.y - s.spawnY))
    local tailX = s.x - (s.vx / speed) * length
    local tailY = s.y - (s.vy / speed) * length

    local right, bottom = w + CULL_MARGIN, h + CULL_MARGIN
    local left, top = -CULL_MARGIN, -CULL_MARGIN
    return (s.x > right and tailX > right)
        or (s.y > bottom and tailY > bottom)
        or (s.x < left and tailX < left)
        or (s.y < top and tailY < top)
end

function Starfield:update(dt)
    self.timer = self.timer - dt
    if self.timer <= 0 then
        self.timer = Math.randRange(self.spawnMin, self.spawnMax)
        self:spawnStar()
    end

    -- Iterate backwards so table.remove during the loop is safe.
    for i = #self.stars, 1, -1 do
        local s = self.stars[i]

        if s.popped then
            s.popped = s.popped + dt
            if s.popped >= POP_FADE then
                table.remove(self.stars, i)
            end
        else
            s.life = s.life + dt

            -- Ease down to ~15% speed near expiry instead of vanishing at full
            -- speed. Computed fresh from the life ratio each frame (not applied
            -- by shrinking s.vx in place), so the curve is frame-rate independent.
            local dying = dyingFactor(s, self.dyingThreshold)
            local speedScale = 1 - dying * 0.95

            s.x = s.x + s.vx * speedScale * dt
            s.y = s.y + s.vy * speedScale * dt

            if s.life >= s.maxLife or fullyOffScreen(s) then
                table.remove(self.stars, i)
            end
        end
    end

    self.burst:update(dt)
end

-- The dying window is split into a bright "flare up" then a fade to nothing.
-- FLARE_FRAC is the fraction of that window where the glow surge peaks.
local FLARE_FRAC = 0.35

local FLARE_GLOW = 1.3

-- Fraction of the dying window spent shifting colors to dead color.
local COLOR_FRAC = 0.12

-- For a star `dying` (0..1) into its dying window, returns head/core opacity,
-- additive-glow intensity, and the colour->flare mix. Glow surges from 1 up to
-- FLARE_GLOW during the flare, then both opacity and glow ease back down to 0.
local function dyingLook(dying)
    local colorMix = math.min(1, dying / COLOR_FRAC)
    if dying <= FLARE_FRAC then
        local t = dying / FLARE_FRAC
        return 1, 1 + t * (FLARE_GLOW - 1), colorMix
    end
    local k = 1 - (dying - FLARE_FRAC) / (1 - FLARE_FRAC)
    return k, FLARE_GLOW * k, colorMix
end

-- A star's current look: head opacity, glow intensity, rgb, and how far into the
-- shift toward its flare colour it is. Both endpoints come from the star itself,
-- so a golden one ages through ambers while an ordinary one goes red.
local function starLook(s, dyingThreshold)
    local dying = dyingFactor(s, dyingThreshold)
    local fade, glowI, colorMix = 1, 1, 0
    if dying > 0 then
        fade, glowI, colorMix = dyingLook(dying)
    end
    local r, g, b = Theme.lerp(s.color, s.flare, colorMix)
    return fade, glowI, r, g, b, colorMix
end

-- Trail geometry
local TRAIL_SEGMENTS = 24  -- lengthwise subdivisions; more = smoother falloff
local TRAIL_CORE_W   = 2.5 -- half-width of the solid core at the head, px
local TRAIL_FEATHER  = 1.5 -- soft edge on each side of the core, px
local TRAIL_WIDTH_RAMP = 60

-- One reused mesh for every star's trail: a (TRAIL_SEGMENTS + 1) x 4 grid of
-- vertices (edge+, core+, core-, edge-) stitched into three bands of triangles.
-- Vertices are rewritten in place per draw via setVertices, so no Mesh (nor its
-- GPU buffer) is allocated per frame and the vertex map is built only once.
local trailMesh, trailVerts

local function buildTrailMesh()
    local verts, map = {}, {}
    for _ = 0, TRAIL_SEGMENTS do
        for _ = 1, 4 do
            verts[#verts + 1] = { 0, 0, 0, 0, 1, 1, 1, 1 }
        end
    end
    for i = 0, TRAIL_SEGMENTS - 1 do
        local a, b = i * 4, (i + 1) * 4 -- first vertex of this column / the next
        for row = 1, 3 do               -- edge+ -> core+, core+ -> core-, core- -> edge-
            map[#map + 1] = a + row
            map[#map + 1] = a + row + 1
            map[#map + 1] = b + row + 1
            map[#map + 1] = a + row
            map[#map + 1] = b + row + 1
            map[#map + 1] = b + row
        end
    end
    local mesh = love.graphics.newMesh(verts, "triangles")
    mesh:setVertexMap(map)
    return mesh, verts
end

local function setVertex(v, x, y, r, g, b, a)
    v[1], v[2] = x, y
    v[5], v[6], v[7], v[8] = r, g, b, a
end

-- Lays the strip down the star's path: (dx, dy) is its unit heading, (nx, ny)
-- the perpendicular, `length` how much of the streak has been earned so far.
local function drawTrail(s, dx, dy, nx, ny, length, r, g, b, fade)
    if not trailMesh then trailMesh, trailVerts = buildTrailMesh() end

    -- s.scale widens the streak for golden stars to match their heavier head.
    local scale = math.min(1, length / TRAIL_WIDTH_RAMP) * (s.scale or 1)
    local coreW = TRAIL_CORE_W * scale
    -- A short cone reaching ahead of the head.
    local nose = math.min(coreW + TRAIL_FEATHER, length)

    for i = 0, TRAIL_SEGMENTS do
        -- t is the fraction of the streak behind the head: column 0 is the tip
        -- just ahead of it, then 1..TRAIL_SEGMENTS run the head (t = 0) to the
        -- tail (t = 1). So the body reaches full width right at the star.
        local t, shape
        if i == 0 then
            t, shape = -nose / length, 0
        else
            t = (i - 1) / (TRAIL_SEGMENTS - 1)
            shape = 1 - t -- linear falloff: the streak's tuned taper
        end
        local px = s.x - dx * length * t
        local py = s.y - dy * length * t
        local core = coreW * shape
        -- The feather keeps its full width all the way to the tip, so the strip
        -- never narrows to a hard-edged sliver anywhere along its length.
        local edge = core + TRAIL_FEATHER
        local alpha = shape * fade

        local o, v = i * 4, trailVerts
        setVertex(v[o + 1], px + nx * edge, py + ny * edge, r, g, b, 0)
        setVertex(v[o + 2], px + nx * core, py + ny * core, r, g, b, alpha)
        setVertex(v[o + 3], px - nx * core, py - ny * core, r, g, b, alpha)
        setVertex(v[o + 4], px - nx * edge, py - ny * edge, r, g, b, 0)
    end

    trailMesh:setVertices(trailVerts)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(trailMesh)
end

local function drawStar(s, dyingThreshold)
    local speed = Math.length(s.vx, s.vy)
    if speed == 0 then return end
    local dx, dy = s.vx / speed, s.vy / speed -- unit direction (unaffected by slowdown)
    local nx, ny = -dy, dx                     -- perpendicular (for trail width)

    -- Grow the trail from nothing as the star travels, capped at its full
    -- length, so it eases into a streak instead of popping in fully drawn. The
    -- path is a straight line, so distance from spawn == distance travelled.
    local length = math.min(s.length, Math.length(s.x - s.spawnX, s.y - s.spawnY))
    -- In flight: a bright white streak at full opacity. On entering the dying
    -- window it flares to coral with a glow surge, then fades out — so the
    -- flare is seen at full brightness before it dims, not after.
    local fade, glowI, r, g, b, colorMix = starLook(s, dyingThreshold)

    -- Below a pixel there is no streak to speak of, only degenerate geometry.
    local drawable = length >= 1

    if s.popped then
        -- Nothing left but the streak dissolving where the star used to be, so
        -- the click reads as the head being knocked out of it rather than the
        -- whole thing being deleted mid-flight. Squared so it eases to nothing
        -- instead of stopping dead at the end of the fade.
        local k = 1 - s.popped / POP_FADE
        if drawable then
            drawTrail(s, dx, dy, nx, ny, length, r, g, b, fade * k * k)
        end
        return
    end

    local hs = 4 * (s.scale or 1)
    local headR = (2 + math.max(0, glowI - 1)) * (s.scale or 1)
    local glowColor = colorMix > 0 and s.flare or { r, g, b }
    Theme.glowRect(s.x - hs, s.y - hs, hs * 2, hs * 2, hs, glowI, glowColor)

    if drawable then
        drawTrail(s, dx, dy, nx, ny, length, r, g, b, fade)
    end

    -- The dot gets an explicit segment count: at this radius LÖVE's default
    -- picks few enough segments to read as a visible polygon.
    love.graphics.setColor(r, g, b, fade)
    love.graphics.circle("fill", s.x, s.y, headR, 24)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Pops the topmost shooting star under (x, y), replacing its head with a
-- particle explosion and leaving the trail behind to fade.
--
-- Returns `hit, golden`: whether a star was hit (so callers can tell the click
-- was consumed) and whether it was a golden one, which is the event an
-- achievement would hang off:
--
--   local hit, golden = self.starfield:mousepressed(x, y, button)
--   if golden then Achievements.unlock("caught_a_golden_star") end
function Starfield:clickAt(x, y)
    local radius = self.clickRadius
    -- Iterate backwards: later stars draw on top, so they win the hit test.
    for i = #self.stars, 1, -1 do
        local s = self.stars[i]
        local dx, dy = s.x - x, s.y - y
        -- Already-popped stars are just a fading streak with no head left to
        -- hit, so they're skipped rather than counted as a second target.
        if not s.popped and dx * dx + dy * dy <= radius * radius then
            -- Faster stars throw a slightly bigger blast, and a golden one
            -- throws golden debris rather than the usual warm spark.
            -- Cloned rather than shared: popping two stars at once should
            -- sound twice, not cut the first pop short.
            local pop = s.golden and "goldenStarExplosion" or "starExplosion"
            Audio.play("sfx", Audios.clone(pop))
            local speed = Math.length(s.vx, s.vy)
            local debris = s.golden and s.color or { 1, 0.4, 0.1 }
            self.burst:spawn(s.x, s.y, debris,
                (0.8 + speed / self.speedMax * 0.4) * (s.scale or 1))
            s.popped = 0 -- update() fades the orphaned trail out, then removes it
            return true, s.golden
        end
    end
    return false
end

-- Convenience wrapper so states can forward the event straight through. Passes
-- clickAt's `hit, golden` pair back to the caller.
function Starfield:mousepressed(x, y, button)
    if button ~= 1 then return false end
    return self:clickAt(x, y)
end

function Starfield:draw()
    for _, s in ipairs(self.stars) do
        drawStar(s, self.dyingThreshold)
    end
    self.burst:draw()
end

return Starfield