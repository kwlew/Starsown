--- Deep-space gas behind the menu. Baked to canvases once, then
-- composited with slow drift each frame.

local Clouds = require("particles.nebula.clouds")
local Layer = require("particles.nebula.layer")
local Math = require("utils.math")
local Motion = require("ui.core.motion")
local Sky = require("particles.sky")
local Theme = require("ui.core.theme")

local Nebula = {}
Nebula.__index = Nebula

local CANVAS_SCALE = 0.5
local OVERSCAN = 0.08 -- room for drift
local SLACK_X, SLACK_Y = Sky.W * OVERSCAN, Sky.H * OVERSCAN

---@param config? table
---@return table
function Nebula.new(config)
    config = config or {}
    return setmetatable({
        layers = {},
        composite = nil,
        bakeState = nil,
        time = 0,
        alpha = config.alpha or 1,
        enabled = config.enabled ~= false,
        seed = config.seed,

        layerCount = config.layerCount or 2,
        layerAlpha = config.layerAlpha or 0.62,
        layerFalloff = config.layerFalloff or 0.62,
        parallaxMin = config.parallaxMin or 0.35,

        cloudsMin = config.cloudsMin or 2,
        cloudsMax = config.cloudsMax or 3,
        centerHole = config.centerHole or 0.30,
        edgeReach = config.edgeReach or 0.52,
        radiusMin = config.radiusMin or 0.16,
        radiusMax = config.radiusMax or 0.30,
        aspectMin = config.aspectMin or 0.45,
        aspectMax = config.aspectMax or 0.85,

        stampsMin = config.stampsMin or 90,
        stampsMax = config.stampsMax or 150,
        stampSizeMin = config.stampSizeMin or 0.28,
        stampSizeMax = config.stampSizeMax or 0.70,
        stampAlphaMin = config.stampAlphaMin or 0.024,
        stampAlphaMax = config.stampAlphaMax or 0.052,

        lanesPerCloud = config.lanesPerCloud or 2,
        laneSegments = config.laneSegments or 3,
        laneTurn = config.laneTurn or 0.35,
        laneAlphaMin = config.laneAlphaMin or 0.03,
        laneAlphaMax = config.laneAlphaMax or 0.06,

        noiseScale = config.noiseScale or 4.5,
        noiseStrength = config.noiseStrength or 0.6,

        colors = config.colors or { Theme.colors.accent, Theme.colors.accentAlt },

        driftRateMin = config.driftRateMin or 0.008,
        driftRateMax = config.driftRateMax or 0.020,
        breatheAmount = config.breatheAmount or 0.10,
        breatheRate = config.breatheRate or 0.18,
    }, Nebula)
end

---@return any # a love.Canvas
function Nebula:ensureComposite()
    if not self.composite then
        self.composite = love.graphics.newCanvas(Math.round(Sky.W * CANVAS_SCALE), Math.round(Sky.H * CANVAS_SCALE))
        self.composite:setFilter("linear", "linear")
    end
    return self.composite
end

--- plans every layer; bakeStep does the work
---@return table self
function Nebula:beginBake()
    if self.seed then math.randomseed(self.seed) end
    self:ensureComposite()

    local plans, total = {}, 0
    for i = 1, self.layerCount do
        local clouds = {}
        for _ = 1, Math.randInt(self.cloudsMin, self.cloudsMax) do
            clouds[#clouds + 1] = Clouds.plan(self, Sky.W, Sky.H)
        end
        plans[i] = { clouds = clouds }
        total = total + 2 + #clouds * 2
    end

    self.bakeState = {
        width = Math.round((Sky.W + SLACK_X) * CANVAS_SCALE),
        height = Math.round((Sky.H + SLACK_Y) * CANVAS_SCALE),
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

---@param i integer
---@param canvas any
---@return table
function Nebula:finishedLayer(i, canvas)
    local depth = self.layerCount > 1 and (i - 1) / (self.layerCount - 1) or 1
    return {
        canvas = Layer.finalize(canvas, self),
        alpha = self.layerAlpha * (self.layerFalloff + (1 - self.layerFalloff) * depth),
        parallax = self.parallaxMin + (1 - self.parallaxMin) * depth,
        driftRateX = Math.randRange(self.driftRateMin, self.driftRateMax),
        driftRateY = Math.randRange(self.driftRateMin, self.driftRateMax),
        phaseX = Math.randAngle(),
        phaseY = Math.randAngle(),
        breathePhase = Math.randAngle(),
    }
end

---@param plan table
---@param blendMode string
---@param paint fun(cfg: table, cloud: table)
---@return boolean # the last cloud was painted
function Nebula:paintNext(plan, blendMode, paint)
    local state = self.bakeState
    local cloud = plan.clouds[state.cloud]
    Layer.paint(plan.canvas, CANVAS_SCALE, SLACK_X / 2, SLACK_Y / 2, blendMode, function()
        paint(self, cloud)
    end)
    state.cloud = state.cloud + 1
    return state.cloud > #plan.clouds
end

--- one small unit of work, so loading keeps animating
---@return boolean done
---@return number progress # 0..1
function Nebula:bakeStep()
    local state = self.bakeState
    if not state then return true, 1 end
    local i = state.layer
    local plan = state.plans[i]

    if state.phase == "prepare" then
        plan.canvas = Layer.newCanvas(state.width, state.height)
        state.phase, state.cloud = "gas", 1
    elseif state.phase == "gas" then
        if self:paintNext(plan, "add", Clouds.stamp) then state.phase, state.cloud = "lanes", 1 end
    elseif state.phase == "lanes" then
        if self:paintNext(plan, "subtract", Clouds.carveLanes) then state.phase = "finalize" end
    else
        self.layers[i] = self:finishedLayer(i, plan.canvas)
        state.layer, state.phase, state.cloud = i + 1, "prepare", 1
    end

    state.completed = state.completed + 1
    local done = state.layer > self.layerCount
    if done then self.bakeState = nil end
    return done, done and 1 or math.min(1, state.completed / state.total)
end

--- the whole bake at once, for an immediate rebuild
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

---@param dt number
function Nebula:update(dt)
    self.time = self.time + dt
end

---@param layer table
---@param drift number # 0 under reduced motion
---@return number dx
---@return number dy
function Nebula:layerOffset(layer, drift)
    local sway = layer.parallax * drift
    local dx = -SLACK_X / 2 + math.sin(self.time * layer.driftRateX + layer.phaseX) * SLACK_X / 2 * sway
    local dy = -SLACK_Y / 2 + math.sin(self.time * layer.driftRateY + layer.phaseY) * SLACK_Y / 2 * sway
    return dx, dy
end

--- composites layers at half res, then covers the window
function Nebula:draw()
    if not self.enabled or self.alpha <= 0 or #self.layers == 0 then return end
    local scale, x, y = Sky.cover(love.graphics.getDimensions())
    local drift = Motion.reduced and 0 or 1
    local breathe = Motion.reduced and 0 or self.breatheAmount

    love.graphics.push("all")
    love.graphics.setCanvas(self:ensureComposite())
    love.graphics.origin()
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setBlendMode("alpha", "premultiplied")
    for _, layer in ipairs(self.layers) do
        local dx, dy = self:layerOffset(layer, drift)
        local a = Math.clamp01(self.alpha * layer.alpha
            * (1 + breathe * math.sin(self.time * self.breatheRate + layer.breathePhase)))
        love.graphics.setColor(a, a, a, a) -- premultiplied
        love.graphics.draw(layer.canvas, dx * CANVAS_SCALE, dy * CANVAS_SCALE)
    end
    love.graphics.pop()

    love.graphics.push("all")
    love.graphics.setBlendMode("alpha", "premultiplied")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.composite, x, y, 0, scale / CANVAS_SCALE)
    love.graphics.pop()
end

return Nebula
