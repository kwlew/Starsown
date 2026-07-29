-- lib/particles/nebula.lua
-- Deep-space gas for the menu backdrop: a few clouds of soft tinted blobs
-- stamped into a Canvas once at load, then drawn as one textured quad per
-- layer per frame.
--
-- Why it's baked rather than drawn live: a cloud is a hundred-odd overlapping
-- stamps, which is far too much to re-issue every frame for a background that
-- never changes shape. Baking makes the per-frame cost one draw call per layer
-- no matter how dense the gas is, and the parallax drift + alpha breathing in
-- draw() supply enough motion that it never reads as a still image.
--
-- Like Stars, this is authored in a fixed 1920x1080 space rather than in the
-- window, so changing resolution in Options never has to regenerate it. Unlike
-- Stars it is *stretched* to the window rather than cropped by it: the sky is a
-- uniform texture and doesn't care which part of it you see, but a nebula is a
-- composition deliberately framed around the UI (see centerHole), and cropping
-- would slide that framing off the menu at any resolution below 1920x1080.
-- Stretching low-frequency gas by a few percent is invisible; stretching a
-- field of point stars would not be.

local Theme = require "lib.ui.theme"
local Math = require "lib.utils.math"

-- The authoring space (see header) and the fraction of it the canvas is baked
-- at. Gas is pure low-frequency detail, so baking at half size is visually free
-- while costing a quarter of the memory and of the bake's fill; the linear
-- upscale on the way back out actually helps, smoothing what would otherwise be
-- faintly visible stamp seams.
local DESIGN_W, DESIGN_H = 1920, 1080
local CANVAS_SCALE = 0.5

-- Extra area baked around the design space, as a fraction of it, giving the
-- drift somewhere to move without ever pulling a canvas edge into view.
local OVERSCAN = 0.08
local SLACK_X, SLACK_Y = DESIGN_W * OVERSCAN, DESIGN_H * OVERSCAN

-- Side of the reusable stamp, in px. Every cloud is drawn from this one
-- texture, scaled and rotated per stamp.
local BLOB_SIZE = 128

-- One soft radial stamp shared by every cloud of every nebula, built on first
-- bake. Alpha falls off as (1 - d^2)^3: exactly zero at the edge, so a stamp
-- never shows a rim, and soft enough through the middle that a few dozen
-- overlapping ones read as gas instead of as a pile of discs.
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

-- Standard normal, Box-Muller. Stamps scatter on a gaussian rather than
-- uniformly inside a radius: a uniform disc has a flat middle and a hard edge,
-- which reads as a painted circle, while a gaussian gives the dense core and
-- the indefinite, wispy boundary that reads as gas.
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
        -- Global opacity multiplier, so a screen can fade the whole thing in or
        -- out without touching the per-layer weights (matches Stars.alpha).
        alpha = config.alpha or 1,
        -- Set to reproduce a nebula you liked while tuning. Reseeds the global
        -- RNG, so it's a debugging aid rather than something to ship set.
        seed = config.seed,

        -- Depth. Layer 1 is the farthest and is drawn first; the nearest is the
        -- brightest and drifts the most, which is the whole parallax effect.
        layerCount = config.layerCount or 2,
        -- Opacity of the nearest layer. Deliberately low: the title, the menu
        -- column and the hint line all sit on top of this, and gas bright
        -- enough to be admired is gas bright enough to make dim text
        -- unreadable. Raise this and check the hint line before keeping it.
        layerAlpha = config.layerAlpha or 0.62,
        layerFalloff = config.layerFalloff or 0.62,  -- farthest layer's share of it
        parallaxMin = config.parallaxMin or 0.35,    -- farthest layer's share of the drift

        -- Cloud placement, as fractions of the design space measured from its
        -- center. centerHole keeps clouds off the middle of the screen, where
        -- the title and the menu live; edgeReach lets them hang off the sides,
        -- which is what stops the backdrop looking like framed wallpaper.
        cloudsMin = config.cloudsMin or 2,
        cloudsMax = config.cloudsMax or 3,
        centerHole = config.centerHole or 0.30,
        edgeReach = config.edgeReach or 0.52,
        radiusMin = config.radiusMin or 0.16, -- x design height
        radiusMax = config.radiusMax or 0.30,
        -- Clouds are stretched along their own axis: a circular one reads as a
        -- smudge, an elongated one reads as structure.
        aspectMin = config.aspectMin or 0.45,
        aspectMax = config.aspectMax or 0.85,

        -- Stamp density. Additive baking accumulates alpha as well as color, so
        -- stamps x alpha is a budget, not a free dial: push the product much
        -- past 1 in the core and the canvas clips to a flat opaque blob.
        stampsMin = config.stampsMin or 90,
        stampsMax = config.stampsMax or 150,
        stampSizeMin = config.stampSizeMin or 0.28, -- x cloud radius
        stampSizeMax = config.stampSizeMax or 0.70,
        stampAlphaMin = config.stampAlphaMin or 0.024,
        stampAlphaMax = config.stampAlphaMax or 0.052,

        -- Dark lanes carved back out after the gas is laid down. Each is a
        -- short chain of stamps rather than one long one; laneTurn is how far
        -- the chain may swing per link, in radians.
        lanesPerCloud = config.lanesPerCloud or 1,
        laneSegments = config.laneSegments or 3,
        laneTurn = config.laneTurn or 0.35,
        laneAlphaMin = config.laneAlphaMin or 0.045,
        laneAlphaMax = config.laneAlphaMax or 0.10,

        -- Each stamp's color is picked between two palette entries, so a cloud
        -- has a core tint and a rim tint rather than one flat hue.
        colors = config.colors or { Theme.colors.accent, Theme.colors.accentAlt },

        -- Motion. The drift rates are in radians/second on a sine, so these are
        -- periods of several minutes: the gas should never be caught moving,
        -- only be somewhere else when you look back.
        driftRateMin = config.driftRateMin or 0.008,
        driftRateMax = config.driftRateMax or 0.020,
        breatheAmount = config.breatheAmount or 0.10,
        breatheRate = config.breatheRate or 0.18,
    }, Nebula)
end

-- One cloud's parameters, in design-space coordinates.
function Nebula:buildCloud()
    local angle = Math.randRange(0, 2 * math.pi)
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
        stamps = math.floor(Math.randRange(self.stampsMin, self.stampsMax + 1)),
    }
end

-- Lays one cloud's gas down. Caller owns the blend mode (additive) and the
-- transform; this only draws.
function Nebula:stampCloud(image, cloud)
    local origin = BLOB_SIZE / 2
    for _ = 1, cloud.stamps do
        -- 0.42 sigma: three standard deviations land just inside cloud.radius,
        -- so the radius means "about where the gas gives out" rather than a
        -- boundary anything is clamped to.
        local ox = gaussian() * cloud.radius * 0.42
        local oy = gaussian() * cloud.radius * 0.42 * cloud.aspect
        local dx, dy = rotate(ox, oy, cloud.tilt)

        -- Distance from the core drives both the fade and the tint, so the
        -- cloud dims and shifts hue outward in one pass.
        local dist = math.min(1, math.sqrt(ox * ox + oy * oy) / cloud.radius)
        local alpha = Math.randRange(self.stampAlphaMin, self.stampAlphaMax) * (0.35 + 0.65 * (1 - dist))
        local r, g, b = Theme.lerp(cloud.core, cloud.rim, dist)

        -- Non-uniform scale plus a random rotation: identical round stamps
        -- betray themselves as circles wherever one lands on a sparse edge.
        local sx = cloud.radius * Math.randRange(self.stampSizeMin, self.stampSizeMax) / BLOB_SIZE
        local sy = sx * Math.randRange(0.6, 1.0)

        love.graphics.setColor(r, g, b, alpha)
        love.graphics.draw(image, cloud.x + dx, cloud.y + dy,
            Math.randRange(0, 2 * math.pi), sx, sy, origin, origin)
    end
end

-- Dark lanes: a few long thin stamps drawn back over the cloud subtractively.
-- Without them a stamped cloud is a smooth gradient blob — the voids are what
-- make it read as structure, and they cost four draws per cloud. Subtract takes
-- the alpha down with the color, so a lane opens a real hole to the background
-- rather than painting a grey streak over the gas.
function Nebula:carveLanes(image, cloud)
    local origin = BLOB_SIZE / 2
    for _ = 1, self.lanesPerCloud do
        -- Start in the cloud's dense middle and walk outward, turning gently at
        -- each link -- the same walk the constellations use, and for the same
        -- reason: one long stamp lays down a straight scratch, while a short
        -- chain of overlapping ones bends the way a dust lane does.
        local ox = gaussian() * cloud.radius * 0.35
        local oy = gaussian() * cloud.radius * 0.35
        local dx, dy = rotate(ox, oy, cloud.tilt)
        local x, y = cloud.x + dx, cloud.y + dy

        -- Roughly along the cloud's own axis, so a lane follows its shape
        -- instead of cutting across it.
        local heading = cloud.tilt + Math.randRange(-0.6, 0.6)
        local segment = cloud.radius * Math.randRange(0.30, 0.55)
        local thickness = cloud.radius * Math.randRange(0.07, 0.16)
        local alpha = Math.randRange(self.laneAlphaMin, self.laneAlphaMax)

        for _ = 1, self.laneSegments do
            love.graphics.setColor(1, 1, 1, alpha)
            love.graphics.draw(image, x, y, heading,
                segment / BLOB_SIZE, thickness / BLOB_SIZE, origin, origin)
            -- Step by less than a full segment so consecutive links overlap and
            -- the lane stays continuous through a turn.
            heading = heading + Math.randRange(-self.laneTurn, self.laneTurn)
            x = x + math.cos(heading) * segment * 0.6
            y = y + math.sin(heading) * segment * 0.6
        end
    end
end

-- Builds every layer's canvas. Call once, at load; everything after this is
-- draw calls. Returns self so it can be chained onto new().
function Nebula:bake()
    if self.seed then math.randomseed(self.seed) end

    local image = getBlob()
    local canvasW = math.floor((DESIGN_W + SLACK_X) * CANVAS_SCALE + 0.5)
    local canvasH = math.floor((DESIGN_H + SLACK_Y) * CANVAS_SCALE + 0.5)
    -- Restored rather than cleared to nil: bake() runs from a loading task, and
    -- assuming it owns the render target would break the moment anything else
    -- baked into a canvas of its own around it.
    local prevCanvas = love.graphics.getCanvas()

    self.layers = {}
    for i = 1, self.layerCount do
        local canvas = love.graphics.newCanvas(canvasW, canvasH)
        canvas:setFilter("linear", "linear")

        love.graphics.setCanvas(canvas)
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.push()
        -- Work in design space with (0, 0) at the design origin; the slack sits
        -- outside it on all four sides.
        love.graphics.scale(CANVAS_SCALE)
        love.graphics.translate(SLACK_X / 2, SLACK_Y / 2)

        local clouds = {}
        for _ = 1, math.floor(Math.randRange(self.cloudsMin, self.cloudsMax + 1)) do
            clouds[#clouds + 1] = self:buildCloud()
        end

        -- Additive gas first, then the lanes cut into it. Additive accumulation
        -- of (color x alpha) into a transparent canvas is already premultiplied
        -- alpha, which is exactly what draw() blends back with.
        love.graphics.setBlendMode("add")
        for _, cloud in ipairs(clouds) do self:stampCloud(image, cloud) end
        love.graphics.setBlendMode("subtract")
        for _, cloud in ipairs(clouds) do self:carveLanes(image, cloud) end
        love.graphics.setBlendMode("alpha")

        love.graphics.pop()

        -- 0 for the farthest layer, 1 for the nearest. A single layer counts as
        -- the near one, so layerCount = 1 isn't silently dimmed.
        local depth = self.layerCount > 1 and (i - 1) / (self.layerCount - 1) or 1
        self.layers[i] = {
            canvas = canvas,
            alpha = self.layerAlpha * (self.layerFalloff + (1 - self.layerFalloff) * depth),
            parallax = self.parallaxMin + (1 - self.parallaxMin) * depth,
            -- Separate x and y rates make the path a slow Lissajous rather than
            -- a line the eye can follow back and forth.
            driftRateX = Math.randRange(self.driftRateMin, self.driftRateMax),
            driftRateY = Math.randRange(self.driftRateMin, self.driftRateMax),
            phaseX = Math.randRange(0, 2 * math.pi),
            phaseY = Math.randRange(0, 2 * math.pi),
            breathePhase = Math.randRange(0, 2 * math.pi),
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

    -- Design space -> window, so the composition keeps its framing at every
    -- resolution (see header). Read per draw rather than cached on resize:
    -- there is nothing to rebuild, so there's nothing for a resize hook to do.
    local w, h = love.graphics.getDimensions()
    local fx, fy = w / DESIGN_W, h / DESIGN_H
    local sx, sy = fx / CANVAS_SCALE, fy / CANVAS_SCALE

    love.graphics.setBlendMode("alpha", "premultiplied")
    for _, layer in ipairs(self.layers) do
        -- Amplitude is capped at half the slack, so the canvas still covers the
        -- design space at every point of the drift and no edge can swing in.
        local dx = -SLACK_X / 2 + math.sin(self.time * layer.driftRateX + layer.phaseX) * SLACK_X / 2 * layer.parallax
        local dy = -SLACK_Y / 2 + math.sin(self.time * layer.driftRateY + layer.phaseY) * SLACK_Y / 2 * layer.parallax

        local a = self.alpha * layer.alpha
            * (1 + self.breatheAmount * math.sin(self.time * self.breatheRate + layer.breathePhase))
        a = math.max(0, math.min(1, a))
        -- Premultiplied: the vertex color's alpha channel does not fade the
        -- canvas' RGB (the blend takes the source color as-is), so a fade has
        -- to be written into all four channels. setColor(1, 1, 1, a) here would
        -- drop the gas' coverage while leaving it at full brightness.
        love.graphics.setColor(a, a, a, a)
        love.graphics.draw(layer.canvas, fx * dx, fy * dy, 0, sx, sy)
    end
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(1, 1, 1, 1)
end

return Nebula
