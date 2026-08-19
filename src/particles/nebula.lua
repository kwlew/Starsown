-- Deep-space gas for the menu backdrop, baked into a Canvas once at load and
-- drawn as one textured quad per layer per frame (too expensive to redraw the
-- stamps live). Authored in a fixed 1920x1080 space like Stars, but stretched
-- to fit the window instead of cropped, since it's a framed composition (see
-- centerHole) rather than a uniform starfield.

local Theme = require "ui.core.theme"
local Math = require "utils.math"
local Motion = require "ui.core.motion"

-- authoring space + fraction it's baked at (gas is low-frequency detail, so
-- baking at half size is visually free and a lot cheaper)
local DESIGN_W, DESIGN_H = 1920, 1080
local CANVAS_SCALE = 0.5

-- margin baked around the design space so drift never reveals a canvas edge
local OVERSCAN = 0.08
local SLACK_X, SLACK_Y = DESIGN_W * OVERSCAN, DESIGN_H * OVERSCAN

local BLOB_SIZE = 128 -- reusable stamp texture size, px

-- one soft radial stamp shared by every cloud; alpha falls off as (1-d^2)^3
-- so it's exactly zero at the edge and never shows a rim
local blob

local function getBlob()
    if blob then return blob end
    local data = love.image.newImageData(BLOB_SIZE, BLOB_SIZE)
    local center = (BLOB_SIZE - 1) / 2
    data:mapPixel(function(x, y)
        local dx, dy = (x - center) / center, (y - center) / center
        local d2 = dx * dx + dy * dy
        if d2 >= 1 then return 1, 1, 1, 0 end
        local a = 1 - d2
        return 1, 1, 1, a * a * a
    end)
    blob = love.graphics.newImage(data)
    blob:setFilter("linear", "linear")
    return blob
end

-- Box-Muller; gaussian scatter gives a dense core + wispy edge instead of a
-- uniform disc's flat middle and hard edge
local function gaussian()
    local u1 = math.max(1e-9, math.random())
    local u2 = math.random()
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
end

local function rotate(x, y, angle)
    local c, s = math.cos(angle), math.sin(angle)
    return x * c - y * s, x * s + y * c
end

local Nebula = {}
Nebula.__index = Nebula

function Nebula.new(config)
    config = config or {}
    return setmetatable({
        layers = {}, -- filled by bake()
        time = 0,
        alpha = config.alpha or 1, -- global fade, on top of per-layer weights
        seed = config.seed,        -- set to reproduce a nebula while tuning

        layerCount = config.layerCount or 2, -- layer 1 = farthest, drawn first
        -- nearest layer's opacity; kept low since UI text sits on top of this
        layerAlpha = config.layerAlpha or 0.62,
        layerFalloff = config.layerFalloff or 0.62, -- farthest layer's share of it
        parallaxMin = config.parallaxMin or 0.35,   -- farthest layer's share of the drift

        cloudsMin = config.cloudsMin or 2,
        cloudsMax = config.cloudsMax or 3,
        centerHole = config.centerHole or 0.30, -- keeps clouds off the title/menu
        edgeReach = config.edgeReach or 0.52,   -- lets clouds hang off the screen edge
        radiusMin = config.radiusMin or 0.16,   -- x design height
        radiusMax = config.radiusMax or 0.30,
        aspectMin = config.aspectMin or 0.45, -- clouds stretched along their axis so they read as structure, not a smudge
        aspectMax = config.aspectMax or 0.85,

        -- stamps x alpha is a budget: push it too far and the core clips to a flat opaque blob
        stampsMin = config.stampsMin or 90,
        stampsMax = config.stampsMax or 150,
        stampSizeMin = config.stampSizeMin or 0.28, -- x cloud radius
        stampSizeMax = config.stampSizeMax or 0.70,
        stampAlphaMin = config.stampAlphaMin or 0.024,
        stampAlphaMax = config.stampAlphaMax or 0.052,

        -- dark lanes carved back out of the gas, each a short chain of stamps
        lanesPerCloud = config.lanesPerCloud or 2,
        laneSegments = config.laneSegments or 3,
        laneTurn = config.laneTurn or 0.35, -- max radians the chain swings per link
        laneAlphaMin = config.laneAlphaMin or 0.001,
        laneAlphaMax = config.laneAlphaMax or 0.005,

        colors = config.colors or { Theme.colors.accent, Theme.colors.accentAlt }, -- core tint / rim tint

        -- radians/sec on a sine; periods of several minutes so drift is never caught moving
        driftRateMin = config.driftRateMin or 0.008,
        driftRateMax = config.driftRateMax or 0.020,
        breatheAmount = config.breatheAmount or 0.10,
        breatheRate = config.breatheRate or 0.18,
    }, Nebula)
end

-- one cloud's parameters, in design-space coordinates
function Nebula:buildCloud()
    local angle = Math.randAngle()
    local ring = Math.randRange(self.centerHole, self.edgeReach)
    local palette = self.colors
    return {
        x = DESIGN_W / 2 + math.cos(angle) * ring * DESIGN_W,
        y = DESIGN_H / 2 + math.sin(angle) * ring * DESIGN_H,
        radius = Math.randRange(self.radiusMin, self.radiusMax) * DESIGN_H,
        tilt = Math.randRange(0, math.pi),
        aspect = Math.randRange(self.aspectMin, self.aspectMax),
        core = palette[math.random(#palette)],
        rim = palette[math.random(#palette)],
        stamps = Math.randInt(self.stampsMin, self.stampsMax),
    }
end

-- lays one cloud's gas down; caller owns the blend mode (additive) and transform
function Nebula:stampCloud(image, cloud)
    local origin = BLOB_SIZE / 2
    for _ = 1, cloud.stamps do
        -- 0.42 sigma keeps ~3 std devs inside cloud.radius, so radius reads as
        -- "where the gas gives out" rather than a hard clamp
        local ox = gaussian() * cloud.radius * 0.42
        local oy = gaussian() * cloud.radius * 0.42 * cloud.aspect
        local dx, dy = rotate(ox, oy, cloud.tilt)

        local dist = math.min(1, Math.length(ox, oy) / cloud.radius)
        local alpha = Math.randRange(self.stampAlphaMin, self.stampAlphaMax) * (0.35 + 0.65 * (1 - dist))
        local r, g, b = Theme.lerp(cloud.core, cloud.rim, dist)

        -- random scale + rotation so identical stamps don't read as circles
        local sx = cloud.radius * Math.randRange(self.stampSizeMin, self.stampSizeMax) / BLOB_SIZE
        local sy = sx * Math.randRange(0.6, 1.0)

        love.graphics.setColor(r, g, b, alpha)
        love.graphics.draw(image, cloud.x + dx, cloud.y + dy,
            Math.randAngle(), sx, sy, origin, origin)
    end
end

-- dark lanes: a few thin stamps drawn back subtractively so the cloud reads
-- as structure instead of a smooth gradient blob
function Nebula:carveLanes(image, cloud)
    local origin = BLOB_SIZE / 2
    for _ = 1, self.lanesPerCloud do
        -- walk outward from the core, turning gently each link (same idea as
        -- the constellation walk) so the lane bends like real dust
        local ox = gaussian() * cloud.radius * 0.35
        local oy = gaussian() * cloud.radius * 0.35
        local dx, dy = rotate(ox, oy, cloud.tilt)
        local x, y = cloud.x + dx, cloud.y + dy

        local heading = cloud.tilt + Math.randRange(-0.6, 0.6)
        local segment = cloud.radius * Math.randRange(0.30, 0.55)
        local thickness = cloud.radius * Math.randRange(0.07, 0.16)
        local alpha = Math.randRange(self.laneAlphaMin, self.laneAlphaMax)

        for _ = 1, self.laneSegments do
            love.graphics.setColor(1, 1, 1, alpha)
            love.graphics.draw(image, x, y, heading,
                segment / BLOB_SIZE, thickness / BLOB_SIZE, origin, origin)
            -- step less than a full segment so links overlap through the turn
            heading = heading + Math.randRange(-self.laneTurn, self.laneTurn)
            x = x + math.cos(heading) * segment * 0.6
            y = y + math.sin(heading) * segment * 0.6
        end
    end
end

-- builds every layer's canvas; call once at load, everything after is draw calls
function Nebula:bake()
    if self.seed then math.randomseed(self.seed) end

    local image = getBlob()
    local canvasW = Math.round((DESIGN_W + SLACK_X) * CANVAS_SCALE)
    local canvasH = Math.round((DESIGN_H + SLACK_Y) * CANVAS_SCALE)
    -- restored, not cleared to nil: runs from a loading task, can't assume it owns the render target
    local prevCanvas = love.graphics.getCanvas()

    self.layers = {}
    for i = 1, self.layerCount do
        local canvas = love.graphics.newCanvas(canvasW, canvasH)
        canvas:setFilter("linear", "linear")

        love.graphics.setCanvas(canvas)
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.push()
        love.graphics.scale(CANVAS_SCALE)
        love.graphics.translate(SLACK_X / 2, SLACK_Y / 2)

        local clouds = {}
        for _ = 1, Math.randInt(self.cloudsMin, self.cloudsMax) do
            clouds[#clouds + 1] = self:buildCloud()
        end

        -- additive gas, then lanes cut into it; additive into a transparent
        -- canvas is already premultiplied alpha, matching how draw() blends it back
        love.graphics.setBlendMode("add")
        for _, cloud in ipairs(clouds) do self:stampCloud(image, cloud) end
        love.graphics.setBlendMode("subtract")
        for _, cloud in ipairs(clouds) do self:carveLanes(image, cloud) end
        love.graphics.setBlendMode("alpha")

        love.graphics.pop()

        -- 0 = farthest, 1 = nearest; single layer counts as the near one
        local depth = self.layerCount > 1 and (i - 1) / (self.layerCount - 1) or 1
        self.layers[i] = {
            canvas = canvas,
            alpha = self.layerAlpha * (self.layerFalloff + (1 - self.layerFalloff) * depth),
            parallax = self.parallaxMin + (1 - self.parallaxMin) * depth,
            driftRateX = Math.randRange(self.driftRateMin, self.driftRateMax),
            driftRateY = Math.randRange(self.driftRateMin, self.driftRateMax),
            phaseX = Math.randAngle(),
            phaseY = Math.randAngle(),
            breathePhase = Math.randAngle(),
        }
    end

    love.graphics.setCanvas(prevCanvas)
    love.graphics.setColor(1, 1, 1, 1)
    return self
end

function Nebula:isBaked()
    return #self.layers > 0
end

function Nebula:update(dt)
    self.time = self.time + dt
end

function Nebula:draw()
    if self.alpha <= 0 or #self.layers == 0 then return end

    -- design space -> window, so the composition keeps its framing at every resolution
    local w, h = love.graphics.getDimensions()
    local fx, fy = w / DESIGN_W, h / DESIGN_H
    local sx, sy = fx / CANVAS_SCALE, fy / CANVAS_SCALE

    -- reduced motion: freeze drift/breathing at their resting position
    -- (sin term's own average) rather than cycling through it
    local driftAmount = Motion.reduced and 0 or 1
    local breatheAmount = Motion.reduced and 0 or self.breatheAmount

    love.graphics.setBlendMode("alpha", "premultiplied")
    for _, layer in ipairs(self.layers) do
        -- amplitude capped at half the slack so the canvas still covers the design space through the whole drift
        local dx = -SLACK_X / 2 + math.sin(self.time * layer.driftRateX + layer.phaseX) * SLACK_X / 2 * layer.parallax * driftAmount
        local dy = -SLACK_Y / 2 + math.sin(self.time * layer.driftRateY + layer.phaseY) * SLACK_Y / 2 * layer.parallax * driftAmount

        local a = self.alpha * layer.alpha
            * (1 + breatheAmount * math.sin(self.time * self.breatheRate + layer.breathePhase))
        a = Math.clamp01(a)
        love.graphics.setColor(a, a, a, a) -- premultiplied: alpha has to go into all 4 channels
        love.graphics.draw(layer.canvas, fx * dx, fy * dy, 0, sx, sy)
    end
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(1, 1, 1, 1)
end

return Nebula
