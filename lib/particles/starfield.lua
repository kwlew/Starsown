-- lib/particles/starfield.lua
-- Shooting stars that streak across the menu sky. They can be clicked to pop,
-- and the ones that aren't burn out on their own into a small puff of embers.
-- TODO: meteor shower mode (a faster spawn profile).

local Theme = require "lib.ui.theme"
local Math = require "lib.utils.math"
local Burst = require "lib.particles.burst"
local Audio = require "lib.audio"
local Audios = require "lib.utils.audios"

local GOLD       = { 1, 0.82, 0.35 }
local GOLD_FLARE = { 1, 0.60, 0.12 }

local EMBER_PROFILE = {
    countMin = 4, countMax = 7,
    speedMin = 14, speedMax = 60,
    lifeMin = 0.25, lifeMax = 0.55,
    sizeMin = 1, sizeMax = 2,
    drag = 5,
}

local function emberBurst(override)
    if not override then return Burst.new(EMBER_PROFILE) end
    local config = {}
    for key, value in pairs(EMBER_PROFILE) do config[key] = value end
    for key, value in pairs(override) do config[key] = value end
    return Burst.new(config)
end

local TWINKLE_AMOUNT = 0.18
local TWINKLE_SPEED_MIN, TWINKLE_SPEED_MAX = 5.5, 9.5

local GOLDEN_TWINKLE_AMOUNT = 0.34
local GOLDEN_TWINKLE_SPEED_MIN, GOLDEN_TWINKLE_SPEED_MAX = 2.4, 3.6

local Starfield = {}
Starfield.__index = Starfield

function Starfield.new(config)
    config = config or {}
    return setmetatable({
        stars = {},
        burst = Burst.new(config.burst),
        embers = emberBurst(config.embers),
        -- How far from a star's center a click still counts as a hit.
        clickRadius = config.clickRadius or 20,
        timer = 0,
        spawnMin = config.spawnMin or 0.4,
        spawnMax = config.spawnMax or 1.5,
        speedMin = config.speedMin or 100,
        speedMax = config.speedMax or 450,
        lengthMin = config.lengthMin or 120,
        lengthMax = config.lengthMax or 500,
        lifeMin = config.lifeMin or 1.5,
        lifeMax = config.lifeMax or 5.2,
        dyingThreshold = config.dyingThreshold or 0.5,
        -- Rare golden stars
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
    local twinkleAmount = TWINKLE_AMOUNT
    local twinkleMin, twinkleMax = TWINKLE_SPEED_MIN, TWINKLE_SPEED_MAX
    if golden then
        speedMin, speedMax = self.goldenSpeedMin, self.goldenSpeedMax
        lifeMin, lifeMax = self.goldenLifeMin, self.goldenLifeMax
        twinkleAmount = GOLDEN_TWINKLE_AMOUNT
        twinkleMin, twinkleMax = GOLDEN_TWINKLE_SPEED_MIN, GOLDEN_TWINKLE_SPEED_MAX
    end

    local x = Math.randRange(-0.05 * w, 0.65 * w)
    local y = Math.randRange(-0.05 * h, 0.03 * h)
    local angle = math.rad(Math.randRange(42, 48))
    local speed = Math.randRange(speedMin, speedMax)
    self.stars[#self.stars + 1] = {
        x = x, y = y,
        spawnX = x, spawnY = y,
        vx = math.cos(angle) * speed,
        vy = math.sin(angle) * speed,
        length = Math.randRange(self.lengthMin, self.lengthMax),
        life = 0,
        maxLife = Math.randRange(lifeMin, lifeMax),
        golden = golden,
        color = golden and GOLD or Theme.colors.star,
        flare = golden and GOLD_FLARE or Theme.colors.accentAlt,
        twinklePhase = Math.randAngle(),
        twinkleSpeed = Math.randRange(twinkleMin, twinkleMax),
        twinkleAmount = twinkleAmount,
        scale = golden and 1.7 or 1,
    }
end

local function dyingFactor(s, threshold)
    local lifeRatio = s.life / s.maxLife
    if lifeRatio <= threshold then return 0 end
    return (lifeRatio - threshold) / (1 - threshold)
end

-- The star's current flicker multiplier, ~1 +/- twinkleAmount.
local function twinkleOf(s)
    local p = s.twinklePhase
    return 1 + s.twinkleAmount * (0.62 * math.sin(p) + 0.38 * math.sin(p * 2.37 + 1.3))
end

local POP_FADE = 0.7

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
    -- Only an edge the star is moving toward may cull it.
    return (s.vx > 0 and s.x > right and tailX > right)
        or (s.vy > 0 and s.y > bottom and tailY > bottom)
        or (s.vx < 0 and s.x < left and tailX < left)
        or (s.vy < 0 and s.y < top and tailY < top)
end


function Starfield:expire(s)
    local w, h = love.graphics.getDimensions()
    if s.x < 0 or s.x > w or s.y < 0 or s.y > h then return end
    local ratio = s.golden and 2 or 1
    self.embers:spawn(s.x, s.y, s.flare, s.scale * ratio)
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
            s.twinklePhase = s.twinklePhase + s.twinkleSpeed * dt

            -- Ease down to ~15% speed near expiry instead of vanishing at full
            -- speed. Computed fresh from the life ratio each frame (not applied
            -- by shrinking s.vx in place), so the curve is frame-rate independent.
            local dying = dyingFactor(s, self.dyingThreshold)
            local speedScale = 1 - dying * 0.95

            s.x = s.x + s.vx * speedScale * dt
            s.y = s.y + s.vy * speedScale * dt

            if s.life >= s.maxLife then
                self:expire(s)
                table.remove(self.stars, i)
            elseif fullyOffScreen(s) then
                -- Left the window rather than died. Nothing to see, so no puff.
                table.remove(self.stars, i)
            end
        end
    end

    self.burst:update(dt)
    self.embers:update(dt)
end

-- The dying window is split into a bright "flare up" then a fade to nothing.
-- FLARE_FRAC is the fraction of that window where the glow surge peaks.
local FLARE_FRAC = 0.35

local FLARE_GLOW = 1.75

-- Fraction of the dying window spent shifting colors to dead color.
local COLOR_FRAC = 0.12

-- How much of its trail a star pulls in as it burns out.
local DYING_RETRACT = 0.65

local function dyingLook(dying)
    local colorMix = math.min(1, dying / COLOR_FRAC)
    if dying <= FLARE_FRAC then
        local t = dying / FLARE_FRAC
        return 1, 1 + t * (FLARE_GLOW - 1), colorMix
    end
    local k = 1 - (dying - FLARE_FRAC) / (1 - FLARE_FRAC)
    return k, FLARE_GLOW * k, colorMix
end

-- A star's current stats.
local function starLook(s, dying)
    local fade, glowI, colorMix = 1, 1, 0
    if dying > 0 then
        fade, glowI, colorMix = dyingLook(dying)
    end
    local r, g, b = Theme.lerp(s.color, s.flare, colorMix)
    return fade, glowI, r, g, b
end

-- Trail geometry
local TRAIL_SEGMENTS = 24  -- lengthwise subdivisions; more = smoother falloff
local TRAIL_CORE_W   = 2.5 -- half-width of the solid core at the head, px
local TRAIL_FEATHER  = 1.5 -- soft edge on each side of the core, px
local TRAIL_WIDTH_RAMP = 60

-- The power to which the trail's alpha is raised to create a smooth fade-out.
local TRAIL_FADE_POW = 1.6

-- Every star's trail is a (TRAIL_SEGMENTS + 1) x 4 grid of vertices (edge+,
-- core+, core-, edge-) stitched into three bands of triangles.
--
-- All of them share ONE mesh, and — importantly — one upload per frame. This
-- used to be one mesh rewritten and drawn per star, which was nearly free on
-- LÖVE 11's OpenGL backend but is not on 12's Vulkan one: each Mesh:setVertices
-- on a buffer that already has a draw pending against it costs a fixed ~0.1 ms,
-- whether it uploads 100 vertices or 1. At 40 stars that alone was 4 ms/frame
-- (measured), which is where the shooting-star framerate drop came from. So
-- every trail is appended into one buffer and sent in a single setVertices +
-- draw: ~0.4 ms for the whole field, and flat in the number of stars.
--
-- Reordering is safe because every trail is drawn additively, and addition
-- commutes — batching them ahead of the heads and halos gives the same image.
local VERTS_PER_TRAIL   = (TRAIL_SEGMENTS + 1) * 4
local INDICES_PER_TRAIL = TRAIL_SEGMENTS * 3 * 6

local trailMesh, trailVerts
local trailCapacity = 0 -- trails the current buffer can hold
local batchCount = 0    -- trails written so far this frame

-- Grows the shared buffer to hold `capacity` trails. Rare: capacity only ever
-- ratchets up, and doubles when it does, so a busy sky pays for this once.
local function ensureTrailMesh(capacity)
    if trailCapacity >= capacity then return end

    capacity = math.max(capacity, trailCapacity * 2, 16)

    local verts, map = {}, {}
    for t = 0, capacity - 1 do
        local base = t * VERTS_PER_TRAIL
        for _ = 1, VERTS_PER_TRAIL do
            verts[#verts + 1] = { 0, 0, 0, 0, 1, 1, 1, 1 }
        end
        for i = 0, TRAIL_SEGMENTS - 1 do
            -- First vertex of this column / the next, offset into this trail's
            -- slice of the shared buffer. The map is 1-based.
            local a, b = base + i * 4, base + (i + 1) * 4
            for row = 1, 3 do -- edge+ -> core+, core+ -> core-, core- -> edge-
                map[#map + 1] = a + row
                map[#map + 1] = a + row + 1
                map[#map + 1] = b + row + 1
                map[#map + 1] = a + row
                map[#map + 1] = b + row + 1
                map[#map + 1] = b + row
            end
        end
    end

    trailMesh = love.graphics.newMesh(verts, "triangles")
    trailMesh:setVertexMap(map)
    trailVerts = verts
    trailCapacity = capacity
end

local function setVertex(v, x, y, r, g, b, a)
    v[1], v[2] = x, y
    v[5], v[6], v[7], v[8] = r, g, b, a
end

-- Appends the strip down the star's path into the shared batch: (dx, dy) is its
-- unit heading, (nx, ny) the perpendicular, `length` how much of the streak has
-- been earned so far. Nothing is drawn here — flushTrails() sends the whole
-- field in one call.
local function addTrail(s, dx, dy, nx, ny, length, r, g, b, fade)
    -- draw() sizes the buffer for the whole field before queuing anything, so
    -- this can't normally trip. It is not grown here on demand: a rebuild
    -- allocates a fresh vertex table, which would silently drop every trail
    -- already queued this frame.
    if batchCount >= trailCapacity then return end

    local base = batchCount * VERTS_PER_TRAIL
    batchCount = batchCount + 1

    -- s.scale widens the streak for golden stars to match their heavier head.
    local scale = math.min(1, length / TRAIL_WIDTH_RAMP) * s.scale
    local coreW = TRAIL_CORE_W * scale
    -- A short cone reaching ahead of the head.
    local nose = math.min(coreW + TRAIL_FEATHER, length)

    for i = 0, TRAIL_SEGMENTS do
        local t, shape
        if i == 0 then
            t, shape = -nose / length, 0
        else
            t = (i - 1) / (TRAIL_SEGMENTS - 1)
            shape = 1 - t
        end
        local px = s.x - dx * length * t
        local py = s.y - dy * length * t
        local core = coreW * shape

        local edge = core + TRAIL_FEATHER
        local alpha = shape ^ TRAIL_FADE_POW * fade

        local o, v = base + i * 4, trailVerts
        setVertex(v[o + 1], px + nx * edge, py + ny * edge, r, g, b, 0)
        setVertex(v[o + 2], px + nx * core, py + ny * core, r, g, b, alpha)
        setVertex(v[o + 3], px - nx * core, py - ny * core, r, g, b, alpha)
        setVertex(v[o + 4], px - nx * edge, py - ny * edge, r, g, b, 0)
    end
end

-- Sends every trail queued this frame as a single additive draw, then resets
-- the batch. Only the slice actually written is uploaded and drawn, so a sky
-- with two stars doesn't pay for a buffer sized by the busiest moment so far.
local function flushTrails()
    if batchCount == 0 then return end

    trailMesh:setVertices(trailVerts, 1, batchCount * VERTS_PER_TRAIL)
    trailMesh:setDrawRange(1, batchCount * INDICES_PER_TRAIL)

    love.graphics.setBlendMode("add")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(trailMesh)
    love.graphics.setBlendMode("alpha")

    batchCount = 0
end


local GLOW_SIZE = 4

local HEAD_RADIUS = 2   -- the head dot.
local HEAD_SWELL  = 1.6 -- px it gains per unit of glow surge.

-- The white-hot middle of the head.
local CORE_FRAC  = 0.55
local CORE_ALPHA = 0.85

-- Scratch colour for the head's halo.
local glowColor = { 0, 0, 0 }

local function drawStar(s, dyingThreshold)
    local speed = Math.length(s.vx, s.vy)
    if speed == 0 then return end
    local dx, dy = s.vx / speed, s.vy / speed -- unit direction (unaffected by slowdown)
    local nx, ny = -dy, dx                     -- perpendicular (for trail width)

    -- Grow the trail from nothing as the star travels.
    local travelled = math.min(s.length, Math.length(s.x - s.spawnX, s.y - s.spawnY))
    -- In flight: a bright streak in the sky's own star tint.
    local dying = dyingFactor(s, dyingThreshold)
    local fade, glowI, r, g, b = starLook(s, dying)

    if s.popped then
        local k = 1 - s.popped / POP_FADE
        if travelled >= 1 then
            addTrail(s, dx, dy, nx, ny, travelled, r, g, b, fade * k * k)
        end
        return
    end

    local length = travelled * (1 - dying * DYING_RETRACT)
    local flicker = twinkleOf(s)

    local hs = GLOW_SIZE * s.scale
    -- The halo takes the same interpolated colour as the head.
    glowColor[1], glowColor[2], glowColor[3] = r, g, b
    Theme.glowRect(s.x - hs, s.y - hs, hs * 2, hs * 2, hs, glowI * flicker, glowColor)

    if length >= 1 then
        addTrail(s, dx, dy, nx, ny, length, r, g, b, fade)
    end

    love.graphics.setBlendMode("add")

    local headAlpha = Math.clamp01(fade * flicker)
    local headR = (HEAD_RADIUS + math.max(0, glowI - 1) * HEAD_SWELL) * s.scale

    love.graphics.setColor(r, g, b, headAlpha)
    love.graphics.circle("fill", s.x, s.y, headR, 24)
    love.graphics.setColor(1, 1, 1, headAlpha * CORE_ALPHA)
    love.graphics.circle("fill", s.x, s.y, headR * CORE_FRAC, 12)

    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(1, 1, 1, 1)
end

-- Returns info about the star clicked.
function Starfield:clickAt(x, y)
    local radius = self.clickRadius
    -- Iterate backwards: later stars draw on top, so they win the hit test.
    for i = #self.stars, 1, -1 do
        local s = self.stars[i]
        local dx, dy = s.x - x, s.y - y
        if not s.popped and dx * dx + dy * dy <= radius * radius then
            -- Faster stars throw a slightly bigger blast.
            local pop = s.golden and "goldenStarExplosion" or "starExplosion"
            Audio.play("sfx", Audios.clone(pop))
            local speed = Math.length(s.vx, s.vy)
            -- Keep color consistent.
            local debris = s.golden and s.color or Theme.colors.accentAlt
            self.burst:spawn(s.x, s.y, debris,
                (0.8 + speed / self.speedMax * 0.4) * s.scale)
            s.popped = 0
            return true, s.golden
        end
    end
    return false, false
end

-- Convenience wrapper so states can forward the event straight through. Passes
-- clickAt's `hit, golden` pair back to the caller.
function Starfield:mousepressed(x, y, button)
    if button ~= 1 then return false, false end
    return self:clickAt(x, y)
end

function Starfield:draw()
    -- Two passes on purpose: drawStar only queues trail geometry, so the whole
    -- field's trails go up in one upload rather than one per star. Heads and
    -- halos are drawn inside drawStar as before. Everything here is additive,
    -- so the split doesn't change the image.
    ensureTrailMesh(#self.stars)

    for _, s in ipairs(self.stars) do
        drawStar(s, self.dyingThreshold)
    end
    flushTrails()

    self.embers:draw()
    self.burst:draw()
end

return Starfield
