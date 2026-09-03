--- Deep-space gas for the menu backdrop, baked into a Canvas once at load and
-- composited from textured layers each frame (too expensive to redraw the
-- stamps live). Authored in a fixed 1920x1080 space like Stars, but stretched
-- to fit the window instead of cropped, since it's a framed composition (see
-- centerHole) rather than a uniform starfield.

local Theme = require "ui.core.theme"
local Math = require "utils.math"
local Motion = require "ui.core.motion"

local DESIGN_W, DESIGN_H = 1920, 1080
local CANVAS_SCALE = 0.5
local COMPOSITE_W = Math.round(DESIGN_W * CANVAS_SCALE)
local COMPOSITE_H = Math.round(DESIGN_H * CANVAS_SCALE)

local OVERSCAN = 0.08
local SLACK_X, SLACK_Y = DESIGN_W * OVERSCAN, DESIGN_H * OVERSCAN

local BLOB_SIZE = 128 -- reusable stamp texture size, px

local blob

--- the one soft round stamp every cloud is built from, generated once. Its
-- alpha falls off cubically, which is what makes overlapping stamps read as
-- gas rather than a pile of discs.
---@return any # a love.Image
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

--- Box-Muller; gaussian scatter gives a dense core + wispy edge instead of a
-- uniform disc's flat middle and hard edge
---@return number # a normally distributed sample, mean 0, deviation 1
local function gaussian()
    local u1 = math.max(1e-9, math.random())
    local u2 = math.random()
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
end

---@param x number
---@param y number
---@param angle number radians
---@return number x
---@return number y
local function rotate(x, y, angle)
    local c, s = math.cos(angle), math.sin(angle)
    return x * c - y * s, x * s + y * c
end

local Nebula = {}
Nebula.__index = Nebula

--- nothing is generated here; see beginBake
---@param config? table # every field below may be overridden
---@return table
function Nebula.new(config)
    config = config or {}
    return setmetatable({
        layers = {}, -- filled by bake()
        composite = nil,
        time = 0,
        alpha = config.alpha or 1, -- global fade, on top of per-layer weights
        enabled = config.enabled ~= false,
        seed = config.seed,        -- set to reproduce a nebula while tuning

        layerCount = config.layerCount or 2, -- layer 1 = farthest, drawn first
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

        stampsMin = config.stampsMin or 90,
        stampsMax = config.stampsMax or 150,
        stampSizeMin = config.stampSizeMin or 0.28, -- x cloud radius
        stampSizeMax = config.stampSizeMax or 0.70,
        stampAlphaMin = config.stampAlphaMin or 0.024,
        stampAlphaMax = config.stampAlphaMax or 0.052,

        lanesPerCloud = config.lanesPerCloud or 2,
        laneSegments = config.laneSegments or 3,
        laneTurn = config.laneTurn or 0.35, -- max radians the chain swings per link
        laneAlphaMin = config.laneAlphaMin or 0.001,
        laneAlphaMax = config.laneAlphaMax or 0.005,

        colors = config.colors or { Theme.colors.accent, Theme.colors.accentAlt }, -- core tint / rim tint

        driftRateMin = config.driftRateMin or 0.008,
        driftRateMax = config.driftRateMax or 0.020,
        breatheAmount = config.breatheAmount or 0.10,
        breatheRate = config.breatheRate or 0.18,
    }, Nebula)
end

--- the reusable half-resolution target every layer is composited into
---@return any # a love.Canvas
function Nebula:ensureComposite()
    if self.composite then return self.composite end
    self.composite = love.graphics.newCanvas(COMPOSITE_W, COMPOSITE_H)
    self.composite:setFilter("linear", "linear")
    return self.composite
end

--- one cloud's parameters, in design-space coordinates. Placed on a ring
-- around the centre, so the middle stays clear for the title and menu.
---@return table cloud
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

--- lays one cloud's gas down: the stamp scattered gaussianly, tinted core-to-rim
-- by distance out. Caller owns the blend mode (additive) and transform.
---@param image any # a love.Image; the blob stamp
---@param cloud table
function Nebula:stampCloud(image, cloud)
    local origin = BLOB_SIZE / 2
    for _ = 1, cloud.stamps do
        local ox = gaussian() * cloud.radius * 0.42
        local oy = gaussian() * cloud.radius * 0.42 * cloud.aspect
        local dx, dy = rotate(ox, oy, cloud.tilt)

        local dist = math.min(1, Math.length(ox, oy) / cloud.radius)
        local alpha = Math.randRange(self.stampAlphaMin, self.stampAlphaMax) * (0.35 + 0.65 * (1 - dist))
        local r, g, b = Theme.lerp(cloud.core, cloud.rim, dist)

        local sx = cloud.radius * Math.randRange(self.stampSizeMin, self.stampSizeMax) / BLOB_SIZE
        local sy = sx * Math.randRange(0.6, 1.0)

        love.graphics.setColor(r, g, b, alpha)
        love.graphics.draw(image, cloud.x + dx, cloud.y + dy,
            Math.randAngle(), sx, sy, origin, origin)
    end
end

--- dark lanes: a few thin stamps drawn back subtractively so the cloud reads
-- as structure instead of a smooth gradient blob
---@param image any # a love.Image; the blob stamp
---@param cloud table
function Nebula:carveLanes(image, cloud)
    local origin = BLOB_SIZE / 2
    for _ = 1, self.lanesPerCloud do
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
            heading = heading + Math.randRange(-self.laneTurn, self.laneTurn)
            x = x + math.cos(heading) * segment * 0.6
            y = y + math.sin(heading) * segment * 0.6
        end
    end
end

---@param prevCanvas any # a love.Canvas, or nil
---@param blendMode any # a love.BlendMode
---@param alphaMode any # a love.BlendAlphaMode
---@param r number
---@param g number
---@param b number
---@param a number
local function restoreGraphics(prevCanvas, blendMode, alphaMode, r, g, b, a)
    love.graphics.setCanvas(prevCanvas)
    love.graphics.setBlendMode(blendMode, alphaMode)
    love.graphics.setColor(r, g, b, a)
end

--- Runs one drawing unit against a layer canvas and restores all graphics
-- state before returning. That makes it safe for incremental baking to pause
-- between units while the loading screen draws normally.
---@param canvas any # a love.Canvas
---@param blendMode any # a love.BlendMode
---@param draw fun() # re-raised after state is restored if it errors
local function drawOnLayer(canvas, blendMode, draw)
    local prevCanvas = love.graphics.getCanvas()
    local prevBlend, prevAlpha = love.graphics.getBlendMode()
    local r, g, b, a = love.graphics.getColor()

    love.graphics.setCanvas(canvas)
    love.graphics.push()
    love.graphics.scale(CANVAS_SCALE)
    love.graphics.translate(SLACK_X / 2, SLACK_Y / 2)
    love.graphics.setBlendMode(blendMode)
    local ok, err = pcall(draw)
    love.graphics.pop()
    restoreGraphics(prevCanvas, prevBlend, prevAlpha, r, g, b, a)
    if not ok then error(err, 0) end
end

--- plans every layer's clouds and readies the incremental bake; bakeStep()
-- does the actual work one unit at a time
---@return table self
function Nebula:beginBake()
    if self.seed then math.randomseed(self.seed) end

    self:ensureComposite()

    local canvasW = Math.round((DESIGN_W + SLACK_X) * CANVAS_SCALE)
    local canvasH = Math.round((DESIGN_H + SLACK_Y) * CANVAS_SCALE)
    local plans = {}
    local total = 0
    for i = 1, self.layerCount do
        local clouds = {}
        for _ = 1, Math.randInt(self.cloudsMin, self.cloudsMax) do
            clouds[#clouds + 1] = self:buildCloud()
        end
        plans[i] = { clouds = clouds }
        total = total + 2 + #clouds * 2 -- prepare/finalize + gas/lane per cloud
    end

    self.bakeState = {
        image = getBlob(),
        canvasW = canvasW,
        canvasH = canvasH,
        plans = plans,
        layer = 1,
        phase = "prepare",
        cloud = 1,
        completed = 0,
        total = math.max(1, total),
    }
    self.layers = {}
    return self
end

--- one unit of work: allocate a layer canvas, stamp one cloud's gas, carve one
-- cloud's lanes, or finalize a layer. Cheap enough to run a few per frame
-- while the loading screen keeps drawing.
---@return boolean done
---@return number # progress, 0..1
function Nebula:bakeStep()
    local state = self.bakeState
    if not state then return true, 1 end

    local i = state.layer
    local plan = state.plans[i]
    if not plan then
        self.bakeState = nil
        return true, 1
    end

    if state.phase == "prepare" then
        local canvas = love.graphics.newCanvas(state.canvasW, state.canvasH)
        canvas:setFilter("linear", "linear")
        local prevCanvas = love.graphics.getCanvas()
        love.graphics.setCanvas(canvas)
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.setCanvas(prevCanvas)
        plan.canvas = canvas
        state.phase = "gas"
        state.cloud = 1
    elseif state.phase == "gas" then
        local cloud = plan.clouds[state.cloud]
        drawOnLayer(plan.canvas, "add", function()
            self:stampCloud(state.image, cloud)
        end)
        state.cloud = state.cloud + 1
        if state.cloud > #plan.clouds then
            state.phase = "lanes"
            state.cloud = 1
        end
    elseif state.phase == "lanes" then
        local cloud = plan.clouds[state.cloud]
        drawOnLayer(plan.canvas, "subtract", function()
            self:carveLanes(state.image, cloud)
        end)
        state.cloud = state.cloud + 1
        if state.cloud > #plan.clouds then state.phase = "finalize" end
    else
        local depth = self.layerCount > 1 and (i - 1) / (self.layerCount - 1) or 1
        self.layers[i] = {
            canvas = plan.canvas,
            alpha = self.layerAlpha * (self.layerFalloff + (1 - self.layerFalloff) * depth),
            parallax = self.parallaxMin + (1 - self.parallaxMin) * depth,
            driftRateX = Math.randRange(self.driftRateMin, self.driftRateMax),
            driftRateY = Math.randRange(self.driftRateMin, self.driftRateMax),
            phaseX = Math.randAngle(),
            phaseY = Math.randAngle(),
            breathePhase = Math.randAngle(),
        }
        state.layer = i + 1
        state.phase = "prepare"
        state.cloud = 1
    end

    state.completed = state.completed + 1
    local done = state.layer > self.layerCount
    local progress = done and 1 or math.min(1, state.completed / state.total)
    if done then self.bakeState = nil end
    return done, progress
end

--- bakes the whole thing in one blocking call, for callers that need the
-- finished canvas immediately (a theme change). The loading screen uses
-- beginBake()/bakeStep() instead, so it can keep drawing.
---@return table self
function Nebula:bake()
    self:beginBake()
    while not self:bakeStep() do end
    return self
end

---@return boolean
function Nebula:isBaked()
    return #self.layers > 0
end

--- only advances the clock; drift and breathing are derived from it at draw
---@param dt number
function Nebula:update(dt)
    self.time = self.time + dt
end

--- composites the drifting layers into the half-res canvas, then stretches that
-- to the window in one draw
function Nebula:draw()
    if not self.enabled or self.alpha <= 0 or #self.layers == 0 then return end

    local w, h = love.graphics.getDimensions()
    local composite = self:ensureComposite()
    local previousCanvas = love.graphics.getCanvas()
    local previousBlend, previousAlphaMode = love.graphics.getBlendMode()
    local previousR, previousG, previousB, previousA = love.graphics.getColor()

    local driftAmount = Motion.reduced and 0 or 1
    local breatheAmount = Motion.reduced and 0 or self.breatheAmount

    love.graphics.setCanvas(composite)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setBlendMode("alpha", "premultiplied")
    for _, layer in ipairs(self.layers) do
        local dx = -SLACK_X / 2 + math.sin(self.time * layer.driftRateX + layer.phaseX) * SLACK_X / 2 * layer.parallax * driftAmount
        local dy = -SLACK_Y / 2 + math.sin(self.time * layer.driftRateY + layer.phaseY) * SLACK_Y / 2 * layer.parallax * driftAmount

        local a = self.alpha * layer.alpha
            * (1 + breatheAmount * math.sin(self.time * self.breatheRate + layer.breathePhase))
        a = Math.clamp01(a)
        love.graphics.setColor(a, a, a, a) -- premultiplied: alpha has to go into all 4 channels
        love.graphics.draw(layer.canvas, dx * CANVAS_SCALE, dy * CANVAS_SCALE)
    end

    love.graphics.setCanvas(previousCanvas)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(composite, 0, 0, 0, w / COMPOSITE_W, h / COMPOSITE_H)

    love.graphics.setBlendMode(previousBlend, previousAlphaMode)
    love.graphics.setColor(previousR, previousG, previousB, previousA)
end

return Nebula
