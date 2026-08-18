-- Shooting stars that streak across the menu sky. Clickable to pop; the ones
-- that aren't burn out on their own into a small puff of embers.
-- TODO: meteor shower mode (a faster spawn profile).

local Theme = require "ui.core.theme"
local Math = require "utils.math"
local Burst = require "particles.burst"
local Audio = require "core.audio"
local Audios = require "utils.audios"

local GOLD       = { 1, 0.82, 0.35 }
local GOLD_FLARE = { 1, 0.60, 0.12 }

-- rainbow stars have no fixed color; head + trail are computed live off the hue
-- wheel. CYCLE_SPEED = wheel-rotations/sec of the star's life; TRAIL_SPAN = how
-- much of the wheel the trail spans head to tail
local RAINBOW_CYCLE_SPEED = 0.15
local RAINBOW_TRAIL_SPAN  = 0.6

-- hue (wraps every 1.0) to RGB at full saturation/value; same sweep as the
-- title's chroma shader (ui/textFactory.lua) but done in Lua since this only
-- needs a couple dozen calls a frame, not one per pixel
local function hueToRgb(hue)
    hue = hue % 1
    local scaled = hue * 6
    local i = math.floor(scaled) % 6
    local f = scaled - math.floor(scaled)
    local q, t = 1 - f, f
    if i == 0 then return 1, t, 0
    elseif i == 1 then return q, 1, 0
    elseif i == 2 then return 0, 1, t
    elseif i == 3 then return 0, q, 1
    elseif i == 4 then return t, 0, 1
    else return 1, 0, q
    end
end

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
        clickRadius = config.clickRadius or 20, -- hit-test radius from a star's center
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
        goldenChance = config.goldenChance or 0.003,
        goldenSpeedMin = config.goldenSpeedMin or 70,
        goldenSpeedMax = config.goldenSpeedMax or 110,
        goldenLifeMin = config.goldenLifeMin or 9,
        goldenLifeMax = config.goldenLifeMax or 13,
        -- rarer than golden and mutually exclusive with it (see spawnStar);
        -- reuses golden's speed/life pacing instead of its own tuning knobs
        rainbowChance = config.rainbowChance or 0.001,
    }, Starfield)
end

function Starfield:spawnStar()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()

    -- golden checked first (more common) so a golden roll can't also roll rainbow
    local golden = math.random() < self.goldenChance
    local rainbow = not golden and math.random() < self.rainbowChance
    local special = golden or rainbow

    local speedMin, speedMax = self.speedMin, self.speedMax
    local lifeMin, lifeMax = self.lifeMin, self.lifeMax
    local twinkleAmount = TWINKLE_AMOUNT
    local twinkleMin, twinkleMax = TWINKLE_SPEED_MIN, TWINKLE_SPEED_MAX
    if special then
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
        rainbow = rainbow,
        -- fallback for the bits that stay a plain color even on a rainbow
        -- star (the burnout ember puff, see expire)
        color = golden and GOLD or Theme.colors.star,
        flare = golden and GOLD_FLARE or Theme.colors.accentAlt,
        twinklePhase = Math.randAngle(),
        twinkleSpeed = Math.randRange(twinkleMin, twinkleMax),
        twinkleAmount = twinkleAmount,
        scale = special and 1.7 or 1,
    }
end

local function dyingFactor(s, threshold)
    local lifeRatio = s.life / s.maxLife
    if lifeRatio <= threshold then return 0 end
    return (lifeRatio - threshold) / (1 - threshold)
end

-- current flicker multiplier, ~1 +/- twinkleAmount
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
    -- only an edge the star is moving toward may cull it
    return (s.vx > 0 and s.x > right and tailX > right)
        or (s.vy > 0 and s.y > bottom and tailY > bottom)
        or (s.vx < 0 and s.x < left and tailX < left)
        or (s.vy < 0 and s.y < top and tailY < top)
end


function Starfield:expire(s)
    local w, h = love.graphics.getDimensions()
    if s.x < 0 or s.x > w or s.y < 0 or s.y > h then return end
    local ratio = (s.golden or s.rainbow) and 2 or 1
    self.embers:spawn(s.x, s.y, s.flare, s.scale * ratio)
end

function Starfield:update(dt)
    self.timer = self.timer - dt
    if self.timer <= 0 then
        self.timer = Math.randRange(self.spawnMin, self.spawnMax)
        self:spawnStar()
    end

    for i = #self.stars, 1, -1 do -- backwards so table.remove mid-loop is safe
        local s = self.stars[i]

        if s.popped then
            s.popped = s.popped + dt
            if s.popped >= POP_FADE then
                table.remove(self.stars, i)
            end
        else
            s.life = s.life + dt
            s.twinklePhase = s.twinklePhase + s.twinkleSpeed * dt

            -- ease down to ~15% speed near expiry instead of vanishing at full
            -- speed; recomputed from the life ratio each frame, not by
            -- shrinking vx/vy in place, so it stays frame-rate independent
            local dying = dyingFactor(s, self.dyingThreshold)
            local speedScale = 1 - dying * 0.95

            s.x = s.x + s.vx * speedScale * dt
            s.y = s.y + s.vy * speedScale * dt

            if s.life >= s.maxLife then
                self:expire(s)
                table.remove(self.stars, i)
            elseif fullyOffScreen(s) then
                table.remove(self.stars, i) -- left the window, not died: no puff
            end
        end
    end

    self.burst:update(dt)
    self.embers:update(dt)
end

-- dying window = a bright flare-up then a fade to nothing; FLARE_FRAC is
-- where in that window the glow surge peaks
local FLARE_FRAC = 0.35

local FLARE_GLOW = 1.75

local COLOR_FRAC = 0.12   -- fraction of the dying window spent shifting to the flare color
local DYING_RETRACT = 0.65 -- how much trail a star pulls in as it burns out

local function dyingLook(dying)
    local colorMix = math.min(1, dying / COLOR_FRAC)
    if dying <= FLARE_FRAC then
        local t = dying / FLARE_FRAC
        return 1, 1 + t * (FLARE_GLOW - 1), colorMix
    end
    local k = 1 - (dying - FLARE_FRAC) / (1 - FLARE_FRAC)
    return k, FLARE_GLOW * k, colorMix
end

local function starLook(s, dying)
    local fade, glowI, colorMix = 1, 1, 0
    if dying > 0 then
        fade, glowI, colorMix = dyingLook(dying)
    end
    local r, g, b
    if s.rainbow then
        -- matches addTrail's t=0 hue so head and trail meet with no seam;
        -- still rides dyingLook's fade/glow, it just doesn't fix on one hue
        r, g, b = hueToRgb(s.life * RAINBOW_CYCLE_SPEED)
    else
        r, g, b = Theme.lerp(s.color, s.flare, colorMix)
    end
    return fade, glowI, r, g, b
end

-- trail geometry
local TRAIL_SEGMENTS = 24  -- lengthwise subdivisions; more = smoother falloff
local TRAIL_CORE_W   = 2.5 -- half-width of the solid core at the head, px
local TRAIL_FEATHER  = 1.5 -- soft edge on each side of the core, px
local TRAIL_WIDTH_RAMP = 60

local TRAIL_FADE_POW = 1.6 -- power the trail's alpha is raised to for a smooth fade-out

-- Every star's trail is a (TRAIL_SEGMENTS+1) x 4 vertex grid (edge+, core+,
-- core-, edge-) stitched into triangles. All trails share ONE mesh and ONE
-- upload+draw per frame instead of one per star: writing to a buffer with a
-- draw already pending against it forces the driver to stall or shadow it, so
-- rewrite-then-draw per star cost a draw call each. Batching into one buffer
-- and issuing a single setVertices + draw makes the whole field one draw call.
-- Reordering trails ahead of heads/halos is safe since everything's additive.
local VERTS_PER_TRAIL   = (TRAIL_SEGMENTS + 1) * 4
local INDICES_PER_TRAIL = TRAIL_SEGMENTS * 3 * 6

local trailMesh, trailVerts
local trailCapacity = 0 -- trails the current buffer can hold
local batchCount = 0    -- trails queued so far this frame

-- grows the shared buffer to hold `capacity` trails; capacity only ratchets up
-- and doubles when it does, so a busy sky pays for this once
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

-- queues the strip down the star's path into the shared batch: (dx,dy) unit
-- heading, (nx,ny) perpendicular, length = streak earned so far. Nothing is
-- drawn here -- flushTrails() sends the whole field in one call.
local function addTrail(s, dx, dy, nx, ny, length, r, g, b, fade)
    -- draw() sizes the buffer for the whole field before queuing, so this
    -- shouldn't trip; not grown here on demand since a rebuild would drop
    -- every trail already queued this frame
    if batchCount >= trailCapacity then return end

    local base = batchCount * VERTS_PER_TRAIL
    batchCount = batchCount + 1

    local scale = math.min(1, length / TRAIL_WIDTH_RAMP) * s.scale -- s.scale widens golden stars' streak
    local coreW = TRAIL_CORE_W * scale
    local nose = math.min(coreW + TRAIL_FEATHER, length) -- short cone reaching ahead of the head

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

        -- a rainbow trail reads its hue off position along the trail (t),
        -- offset by the star's life so the streak slowly turns over; t=0
        -- lands on the same hue as starLook's head color, so no seam
        local sr, sg, sb = r, g, b
        if s.rainbow then
            sr, sg, sb = hueToRgb(s.life * RAINBOW_CYCLE_SPEED - t * RAINBOW_TRAIL_SPAN)
        end

        local o, v = base + i * 4, trailVerts
        setVertex(v[o + 1], px + nx * edge, py + ny * edge, sr, sg, sb, 0)
        setVertex(v[o + 2], px + nx * core, py + ny * core, sr, sg, sb, alpha)
        setVertex(v[o + 3], px - nx * core, py - ny * core, sr, sg, sb, alpha)
        setVertex(v[o + 4], px - nx * edge, py - ny * edge, sr, sg, sb, 0)
    end
end

-- sends every trail queued this frame as one additive draw, then resets the
-- batch; only the written slice is uploaded/drawn
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

local HEAD_RADIUS = 2   -- the head dot
local HEAD_SWELL  = 1.6 -- px gained per unit of glow surge

local CORE_FRAC  = 0.55 -- white-hot middle of the head
local CORE_ALPHA = 0.85

local glowColor = { 0, 0, 0 } -- scratch color for the head's halo

local function drawStar(s, dyingThreshold)
    local speed = Math.length(s.vx, s.vy)
    if speed == 0 then return end
    local dx, dy = s.vx / speed, s.vy / speed -- unit direction
    local nx, ny = -dy, dx                     -- perpendicular, for trail width

    local travelled = math.min(s.length, Math.length(s.x - s.spawnX, s.y - s.spawnY))
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

-- picked fresh each pop so the sound doesn't always ring out identically;
-- golden keeps one dedicated sound so it stands apart as the rare one
local POP_SOUNDS = { "starExplosion", "starExplosion2", "starExplosion3" }

local function popSound(golden)
    if golden then return "goldenStarExplosion" end
    return POP_SOUNDS[Math.randInt(1, #POP_SOUNDS)]
end

function Starfield:clickAt(x, y)
    local radius = self.clickRadius
    for i = #self.stars, 1, -1 do -- backwards: later stars draw on top, so they win the hit test
        local s = self.stars[i]
        local dx, dy = s.x - x, s.y - y
        if not s.popped and dx * dx + dy * dy <= radius * radius then
            Audio.play("sfx", Audios.clone(popSound(s.golden)))
            local speed = Math.length(s.vx, s.vy)
            local debris = s.golden and s.color or Theme.fixedColors.starPop
            self.burst:spawn(s.x, s.y, debris, -- faster stars throw a bigger blast
                (0.8 + speed / self.speedMax * 0.4) * s.scale)
            s.popped = 0
            return true, s.golden, s.rainbow
        end
    end
    return false, false, false
end

function Starfield:mousepressed(x, y, button)
    if button ~= 1 then return false, false, false end
    return self:clickAt(x, y)
end

function Starfield:draw()
    -- two passes on purpose: drawStar only queues trail geometry, so the
    -- whole field's trails go up in one upload+draw instead of one per star
    ensureTrailMesh(#self.stars)

    for _, s in ipairs(self.stars) do
        drawStar(s, self.dyingThreshold)
    end
    flushTrails()

    self.embers:draw()
    self.burst:draw()
end

return Starfield
