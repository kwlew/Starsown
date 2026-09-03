--- Shooting stars that streak across the menu sky. Clickable to pop; the ones
-- that aren't burn out on their own into a small puff of embers.
-- TODO: meteor shower mode (a faster spawn profile).

local Theme = require "ui.core.theme"
local Math = require "utils.math"
local Burst = require "particles.burst"
local Audio = require "core.audio"
local Audios = require "utils.audios"
local Motion = require "ui.core.motion"

local REDUCED_SPAWN_SCALE = 2.5
local REDUCED_SPEED_SCALE = 0.5

local GOLD       = Theme.fixedColors.gold
local GOLD_FLARE = Theme.fixedColors.goldFlare

local RAINBOW_CYCLE_SPEED = 0.15
local RAINBOW_TRAIL_SPAN  = 0.6

--- hue (wraps every 1.0) to RGB at full saturation/value; same sweep as the
-- title's chroma shader (ui/textFactory.lua) but done in Lua since this only
-- needs a couple dozen calls a frame, not one per pixel
---@param hue number # wraps every 1.0
---@return number r
---@return number g
---@return number b
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

---@param override? table # fields layered over EMBER_PROFILE
---@return table
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

local GLOW_TEXTURE_SIZE = 32
local HEAD_TEXTURE_SIZE = 16
local glowImage
local glowBatch
local glowCapacity = 0
local headImage
local headBatch
local headCapacity = 0

--- the soft radial texture every star's halo is one sprite of, generated once
---@return any # a love.Image
local function getGlowImage()
    if glowImage then return glowImage end

    local data = love.image.newImageData(GLOW_TEXTURE_SIZE, GLOW_TEXTURE_SIZE)
    local center = (GLOW_TEXTURE_SIZE - 1) / 2
    data:mapPixel(function(x, y)
        local dx, dy = (x - center) / center, (y - center) / center
        local d2 = dx * dx + dy * dy
        if d2 >= 1 then return 1, 1, 1, 0 end
        local alpha = 1 - d2
        return 1, 1, 1, alpha * alpha
    end)
    glowImage = love.graphics.newImage(data)
    glowImage:setFilter("linear", "linear")
    return glowImage
end

--- grows by doubling, so a busy frame doesn't reallocate per star
---@param capacity integer
---@return any # a love.SpriteBatch
local function ensureGlowBatch(capacity)
    if glowBatch and glowCapacity >= capacity then return glowBatch end
    glowCapacity = math.max(capacity, glowCapacity * 2, 16)
    glowBatch = love.graphics.newSpriteBatch(getGlowImage(), glowCapacity, "stream")
    return glowBatch
end

--- the antialiased dot every star's head is drawn from, generated once
---@return any # a love.Image
local function getHeadImage()
    if headImage then return headImage end

    local data = love.image.newImageData(HEAD_TEXTURE_SIZE, HEAD_TEXTURE_SIZE)
    local center = (HEAD_TEXTURE_SIZE - 1) / 2
    local radius = center - 0.5
    data:mapPixel(function(x, y)
        local dx, dy = x - center, y - center
        local alpha = Math.clamp01(radius + 1 - math.sqrt(dx * dx + dy * dy))
        return 1, 1, 1, alpha
    end)
    headImage = love.graphics.newImage(data)
    headImage:setFilter("linear", "linear")
    return headImage
end

---@param capacity integer # two sprites per star: the tinted head and its white core
---@return any # a love.SpriteBatch
local function ensureHeadBatch(capacity)
    if headBatch and headCapacity >= capacity then return headBatch end
    headCapacity = math.max(capacity, headCapacity * 2, 32)
    headBatch = love.graphics.newSpriteBatch(getHeadImage(), headCapacity, "stream")
    return headBatch
end

local Starfield = {}
Starfield.__index = Starfield

---@param config? table # every field below may be overridden; `burst` and `embers` are passed through to Burst.new
---@return table
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
        rainbowChance = config.rainbowChance or 0.001,
    }, Starfield)
end

--- one streak entering from the upper left. Golden and rainbow stars are rare
-- variants: slower, longer-lived and larger, so a player has time to notice
-- and click one.
function Starfield:spawnStar()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()

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
    if Motion.reduced then speed = speed * REDUCED_SPEED_SCALE end
    local dirX, dirY = math.cos(angle), math.sin(angle)
    self.stars[#self.stars + 1] = {
        x = x, y = y,
        dirX = dirX, dirY = dirY,
        speed = speed,
        travelled = 0,
        length = Math.randRange(self.lengthMin, self.lengthMax),
        life = 0,
        maxLife = Math.randRange(lifeMin, lifeMax),
        golden = golden,
        rainbow = rainbow,
        color = golden and GOLD or Theme.colors.star,
        flare = golden and GOLD_FLARE or Theme.colors.accentAlt,
        twinklePhase = Math.randAngle(),
        twinkleSpeed = Math.randRange(twinkleMin, twinkleMax),
        twinkleAmount = twinkleAmount,
        scale = special and 1.7 or 1,
    }
end

---@param s table
---@param threshold number # life fraction the burn-out begins at
---@return number # 0..1, 0 until the threshold is passed
local function dyingFactor(s, threshold)
    local lifeRatio = s.life / s.maxLife
    if lifeRatio <= threshold then return 0 end
    return (lifeRatio - threshold) / (1 - threshold)
end

--- current flicker multiplier, ~1 +/- twinkleAmount
---@param s table
---@return number
local function twinkleOf(s)
    local p = s.twinklePhase
    return 1 + s.twinkleAmount * (0.62 * math.sin(p) + 0.38 * math.sin(p * 2.37 + 1.3))
end

local POP_FADE = 0.7

local CULL_MARGIN = 64

--- true only once the trail's tail has cleared the window too, not just the head
---@param s table
---@param w number
---@param h number
---@return boolean
local function fullyOffScreen(s, w, h)
    local length = math.min(s.length, s.travelled)
    local tailX = s.x - s.dirX * length
    local tailY = s.y - s.dirY * length

    local right, bottom = w + CULL_MARGIN, h + CULL_MARGIN
    local left, top = -CULL_MARGIN, -CULL_MARGIN
    return (s.dirX > 0 and s.x > right and tailX > right)
        or (s.dirY > 0 and s.y > bottom and tailY > bottom)
        or (s.dirX < 0 and s.x < left and tailX < left)
        or (s.dirY < 0 and s.y < top and tailY < top)
end


--- burning out inside the window leaves a puff of embers; one that expires
-- off-screen leaves nothing
---@param s table
function Starfield:expire(s)
    local w, h = love.graphics.getDimensions()
    if s.x < 0 or s.x > w or s.y < 0 or s.y > h then return end
    local ratio = (s.golden or s.rainbow) and 2 or 1
    self.embers:spawn(s.x, s.y, s.flare, s.scale * ratio)
end

--- spawns on a timer, advances every star (slowing as it burns out), and
-- retires the ones that died or left the window
---@param dt number
function Starfield:update(dt)
    self.timer = self.timer - dt
    if self.timer <= 0 then
        self.timer = Math.randRange(self.spawnMin, self.spawnMax)
        if Motion.reduced then self.timer = self.timer * REDUCED_SPAWN_SCALE end
        self:spawnStar()
    end

    local w, h = love.graphics.getDimensions()
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

            local dying = dyingFactor(s, self.dyingThreshold)
            local speedScale = 1 - dying * 0.95
            local distance = s.speed * speedScale * dt

            s.x = s.x + s.dirX * distance
            s.y = s.y + s.dirY * distance
            s.travelled = s.travelled + distance

            if s.life >= s.maxLife then
                self:expire(s)
                table.remove(self.stars, i)
            elseif fullyOffScreen(s, w, h) then
                table.remove(self.stars, i) -- left the window, not died: no puff
            end
        end
    end

    self.burst:update(dt)
    self.embers:update(dt)
end

local FLARE_FRAC = 0.35

local FLARE_GLOW = 1.75

local COLOR_FRAC = 0.12   -- fraction of the dying window spent shifting to the flare color
local DYING_RETRACT = 0.65 -- how much trail a star pulls in as it burns out

--- the burn-out: a flare that brightens, then fades out
---@param dying number # 0..1
---@return number fade
---@return number glowIntensity
---@return number # colorMix, toward the flare colour
local function dyingLook(dying)
    local colorMix = math.min(1, dying / COLOR_FRAC)
    if dying <= FLARE_FRAC then
        local t = dying / FLARE_FRAC
        return 1, 1 + t * (FLARE_GLOW - 1), colorMix
    end
    local k = 1 - (dying - FLARE_FRAC) / (1 - FLARE_FRAC)
    return k, FLARE_GLOW * k, colorMix
end

---@param s table
---@param dying number # 0..1
---@return number fade
---@return number glowIntensity
---@return number r
---@return number g
---@return number b
local function starLook(s, dying)
    local fade, glowI, colorMix = 1, 1, 0
    if dying > 0 then
        fade, glowI, colorMix = dyingLook(dying)
    end
    local r, g, b
    if s.rainbow then
        r, g, b = hueToRgb(s.life * RAINBOW_CYCLE_SPEED)
    else
        r, g, b = Theme.lerp(s.color, s.flare, colorMix)
    end
    return fade, glowI, r, g, b
end

local TRAIL_SEGMENTS = 12
local TRAIL_CORE_W   = 2.5 -- half-width of the solid core at the head, px
local TRAIL_FEATHER  = 1.5 -- soft edge on each side of the core, px
local TRAIL_WIDTH_RAMP = 60

local TRAIL_FADE_POW = 1.6 -- power the trail's alpha is raised to for a smooth fade-out

local VERTS_PER_TRAIL   = (TRAIL_SEGMENTS + 1) * 4
local INDICES_PER_TRAIL = TRAIL_SEGMENTS * 3 * 6

local trailMesh, trailVerts
local trailCapacity = 0 -- trails the current buffer can hold
local batchCount = 0    -- trails queued so far this frame

--- allocates one shared mesh big enough for `capacity` trails, with its vertex
-- map prebuilt -- every trail on screen is then one draw call
---@param capacity integer
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

---@param v table # a vertex row in the shared buffer
---@param x number
---@param y number
---@param r number
---@param g number
---@param b number
---@param a number
local function setVertex(v, x, y, r, g, b, a)
    v[1], v[2] = x, y
    v[5], v[6], v[7], v[8] = r, g, b, a
end

--- writes one tapering streak into the shared buffer: a solid core between two
-- transparent edges, plus a short nose reaching ahead of the head
---@param s table
---@param dx number heading
---@param dy number heading
---@param nx number # normal to the heading
---@param ny number # normal to the heading
---@param length number
---@param r number
---@param g number
---@param b number
---@param fade number # 0..1
local function addTrail(s, dx, dy, nx, ny, length, r, g, b, fade)
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

--- sends every trail queued this frame as one additive draw, then resets the
-- batch; only the written slice is uploaded/drawn
local function flushTrails()
    if batchCount == 0 then return end

    trailMesh:setVertices(trailVerts, 1, batchCount * VERTS_PER_TRAIL)
    trailMesh:setDrawRange(1, batchCount * INDICES_PER_TRAIL)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(trailMesh)

    batchCount = 0
end


local GLOW_SIZE = 4

local HEAD_RADIUS = 2   -- the head dot
local HEAD_SWELL  = 1.6 -- px gained per unit of glow surge

local CORE_FRAC  = 0.55 -- white-hot middle of the head
local CORE_ALPHA = 0.85

--- adds one star's halo, trail and head to the frame's batches. A popped star
-- keeps only its trail, fading out.
---@param s table
---@param dyingThreshold number
---@param glows any # a love.SpriteBatch
---@param heads any # a love.SpriteBatch
local function queueStar(s, dyingThreshold, glows, heads)
    if s.speed == 0 then return end
    local dx, dy = s.dirX, s.dirY
    local nx, ny = -dy, dx

    local travelled = math.min(s.length, s.travelled)
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
    local glowRadius = hs + Theme.metrics.glowLayers * Theme.metrics.glowSpread
    local glowScale = glowRadius * 2 / GLOW_TEXTURE_SIZE
    glows:setColor(r, g, b, Math.clamp01(glowI * flicker * 0.5))
    glows:add(s.x, s.y, 0, glowScale, glowScale,
        GLOW_TEXTURE_SIZE / 2, GLOW_TEXTURE_SIZE / 2)

    if length >= 1 then
        addTrail(s, dx, dy, nx, ny, length, r, g, b, fade)
    end

    local headAlpha = Math.clamp01(fade * flicker)
    local headR = (HEAD_RADIUS + math.max(0, glowI - 1) * HEAD_SWELL) * s.scale
    local outerScale = headR * 2 / HEAD_TEXTURE_SIZE
    local coreScale = outerScale * CORE_FRAC
    heads:setColor(r, g, b, headAlpha)
    heads:add(s.x, s.y, 0, outerScale, outerScale,
        HEAD_TEXTURE_SIZE / 2, HEAD_TEXTURE_SIZE / 2)
    heads:setColor(1, 1, 1, headAlpha * CORE_ALPHA)
    heads:add(s.x, s.y, 0, coreScale, coreScale,
        HEAD_TEXTURE_SIZE / 2, HEAD_TEXTURE_SIZE / 2)
end

local POP_SOUNDS = { "starExplosion", "starExplosion2", "starExplosion3" }

---@param golden boolean
---@return string # a name utils/audios.lua has preloaded
local function popSound(golden)
    if golden then return "goldenStarExplosion" end
    return POP_SOUNDS[Math.randInt(1, #POP_SOUNDS)]
end

--- pops the topmost star under the point, if any
---@param x number
---@param y number
---@return boolean popped
---@return boolean golden
---@return boolean rainbow
function Starfield:clickAt(x, y)
    local radius = self.clickRadius
    for i = #self.stars, 1, -1 do -- backwards: later stars draw on top, so they win the hit test
        local s = self.stars[i]
        local dx, dy = s.x - x, s.y - y
        if not s.popped and dx * dx + dy * dy <= radius * radius then
            Audio.play("sfx", Audios.clone(popSound(s.golden)), { volume = 0.50 })
            local debris = s.golden and s.color or Theme.fixedColors.starPop
            self.burst:spawn(s.x, s.y, debris, -- faster stars throw a bigger blast
                (0.8 + s.speed / self.speedMax * 0.4) * s.scale)
            s.popped = 0
            return true, s.golden, s.rainbow
        end
    end
    return false, false, false
end

---@param x number
---@param y number
---@param button integer
---@return boolean popped
---@return boolean golden
---@return boolean rainbow
function Starfield:mousepressed(x, y, button)
    if button ~= 1 then return false, false, false end
    return self:clickAt(x, y)
end

--- glows, trails, heads and both burst pools, all in one additive section --
-- the batches are why a sky full of stars stays a handful of draw calls
function Starfield:draw()
    local starCount = #self.stars
    ensureTrailMesh(starCount)
    local glows = ensureGlowBatch(starCount)
    local heads = ensureHeadBatch(starCount * 2)
    glows:clear()
    heads:clear()

    for _, s in ipairs(self.stars) do
        queueStar(s, self.dyingThreshold, glows, heads)
    end

    love.graphics.setBlendMode("add")
    love.graphics.setColor(1, 1, 1, 1)
    if glows:getCount() > 0 then love.graphics.draw(glows) end
    flushTrails()
    if heads:getCount() > 0 then love.graphics.draw(heads) end

    self.embers:draw(true)
    self.burst:draw(true)

    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(1, 1, 1, 1)
end

return Starfield
