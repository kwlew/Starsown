--- The fixed night sky: twinkling stars and a few constellations.
-- Built in Sky's design space, scaled to cover the window.

local Constellations = require("particles.stars.constellations")
local Ease = require("utils.ease")
local Geometry = require("particles.stars.geometry")
local Math = require("utils.math")
local Motion = require("ui.core.motion")
local Render = require("particles.stars.render")
local Sky = require("particles.sky")
local Theme = require("ui.core.theme")

local Stars = {}
Stars.__index = Stars

-- the menu's title and button column, as sky fractions
local KEEP_OUT = {
    { 0.25, 0.04, 0.75, 0.34 },
    { 0.33, 0.34, 0.67, 0.80 },
}
local KEEP_OUT_PAD = 28

local TRACE_DELAY = 0.4    -- s before the first line draws
local TRACE_STAGGER = 0.35 -- s between constellations
local TRACE_LINK = 0.28    -- s per link

local HOVER_REACH = 80 -- sky px from a line
local HOVER_RATE = 8
local HOVER_ALPHA = 0.6

---@param config? table
---@return table
function Stars.new(config)
    config = config or {}
    return setmetatable({
        stars = {},
        links = {},          -- { x1, y1, x2, y2, group, depth }
        constellations = {}, -- { x, y, radius, glow }
        pointerX = nil,
        pointerY = nil,
        mesh = nil,
        time = 0,
        alpha = config.alpha or 1,
        enabled = config.enabled ~= false,
        amountMin = config.amountMin or 150,
        amountMax = config.amountMax or 190,
        oscillation = config.brightnessOscillation or 0.7,
        blinkSpeedMin = config.blinkSpeedMin or 0.3,
        blinkSpeedMax = config.blinkSpeedMax or 1.2,
        sizeMin = config.sizeMin or 0.9,
        sizeMax = config.sizeMax or 2.4,
        featuredSizeMin = config.featuredSizeMin or 1.7,
        featuredSizeMax = config.featuredSizeMax or 2.6,
        tintMax = config.tintMax or 0.6,
        countMin = config.constellationCountMin or 3,
        countMax = config.constellationCountMax or 6,
        figure = {
            starsMin = config.constellationStarsMin or 6,
            starsMax = config.constellationStarsMax or 10,
            link = config.constellationLink or 120,
            gap = config.constellationGap or 60,
            loopChance = config.constellationLoopChance or 0.35,
            keepOut = {},
        },
        keepOut = config.keepOut or KEEP_OUT,
        lineAlpha = config.lineAlpha or 0.2,
    }, Stars)
end

--- featured stars anchor constellations: bigger and brighter
---@param x number
---@param y number
---@param featured? boolean
---@return table
function Stars:newStar(x, y, featured)
    local size, brightness
    if featured then
        size = Math.randRange(self.featuredSizeMin, self.featuredSizeMax)
        brightness = Math.randRange(0.85, 1.0)
    else
        local t = math.random() ^ 3 -- mostly small, the odd large one
        size = self.sizeMin + (self.sizeMax - self.sizeMin) * t
        brightness = Math.randRange(0.6, 0.85) + 0.15 * t
    end
    return {
        x = x, y = y, size = size, brightness = brightness,
        blinkPhase = Math.randAngle(),
        blinkSpeed = Math.randRange(self.blinkSpeedMin, self.blinkSpeedMax),
        tint = math.random(0, 1),
        tintAmount = self.tintMax * math.random() ^ 2,
    }
end

---@param w number
---@param h number
---@return number[][]
function Stars:keepOutRects(w, h)
    local rects = {}
    for i, r in ipairs(self.keepOut) do
        rects[i] = { r[1] * w - KEEP_OUT_PAD, r[2] * h - KEEP_OUT_PAD,
                     r[3] * w + KEEP_OUT_PAD, r[4] * h + KEEP_OUT_PAD }
    end
    return rects
end

---@param figure table
function Stars:addConstellation(figure)
    local group = #self.constellations + 1
    for _, p in ipairs(figure.points) do
        self.stars[#self.stars + 1] = self:newStar(p.x, p.y, true)
    end
    for _, link in ipairs(figure.links) do
        link.group = group
        self.links[#self.links + 1] = link
    end
    self.constellations[group] = { x = figure.x, y = figure.y, radius = figure.radius, glow = 0 }
end

--- regenerates the sky; resizing never reshuffles it
function Stars:spawnStars()
    local w, h = Sky.W, Sky.H
    self.stars, self.links, self.constellations = {}, {}, {}
    self.figure.keepOut = self:keepOutRects(w, h)

    for _ = 1, Math.randInt(self.amountMin, self.amountMax) do
        self.stars[#self.stars + 1] = self:newStar(Math.randRange(0, w), Math.randRange(0, h))
    end
    for _ = 1, Math.randInt(self.countMin, self.countMax) do
        local figure = Constellations.generate(self.figure, self.constellations, w, h)
        if figure then self:addConstellation(figure) end
    end

    self.mesh = Render.buildMesh(self.stars)
    Render.shader()
end

--- screen-space pointer; nil when nothing points at the sky
---@param x number|nil
---@param y number|nil
function Stars:setPointer(x, y)
    if not x or not y then
        self.pointerX, self.pointerY = nil, nil
        return
    end
    self.pointerX, self.pointerY = Sky.toSky(x, y)
end

---@param link table
---@return number # 0..1 of the line drawn so far
function Stars:traceProgress(link)
    if Motion.reduced then return 1 end
    local start = TRACE_DELAY + (link.group - 1) * TRACE_STAGGER + link.depth * TRACE_LINK
    return Ease.outCubic(Math.clamp01((self.time - start) / TRACE_LINK))
end

---@param dt number
function Stars:update(dt)
    self.time = self.time + dt

    for _, c in ipairs(self.constellations) do c.lit = false end
    if self.pointerX then
        for _, link in ipairs(self.links) do
            if Geometry.distanceToSegment(self.pointerX, self.pointerY, link) < HOVER_REACH then
                self.constellations[link.group].lit = true
            end
        end
    end
    for _, c in ipairs(self.constellations) do
        c.glow = Math.damp(c.glow, c.lit and 1 or 0, HOVER_RATE, dt)
    end
end

---@param scale number
function Stars:drawLinks(scale)
    local c = Theme.colors
    love.graphics.setLineWidth(1 / scale) -- one screen pixel
    for _, link in ipairs(self.links) do
        local t = self:traceProgress(link)
        if t > 0 then
            local glow = self.constellations[link.group].glow
            local r, g, b = Theme.lerp(c.textDim, c.accentBright, glow)
            love.graphics.setColor(r, g, b, (self.lineAlpha + (HOVER_ALPHA - self.lineAlpha) * glow) * self.alpha)
            love.graphics.line(link[1], link[2],
                link[1] + (link[3] - link[1]) * t, link[2] + (link[4] - link[2]) * t)
        end
    end
end

function Stars:drawStars()
    local shader = Render.shader()
    shader:send("time", self.time)
    shader:send("oscillation", Motion.reduced and 0 or self.oscillation)
    shader:send("tintA", Math.Color.normalized(Theme.colors.accent))
    shader:send("tintB", Math.Color.normalized(Theme.colors.accentAlt))
    Theme.setColor(Theme.colors.star, self.alpha)
    love.graphics.setShader(shader)
    love.graphics.draw(self.mesh)
end

function Stars:draw()
    if not self.enabled or self.alpha <= 0 or not self.mesh then return end
    local scale, x, y = Sky.cover(love.graphics.getDimensions())
    love.graphics.push("all")
    love.graphics.translate(x, y)
    love.graphics.scale(scale)
    self:drawLinks(scale)
    self:drawStars()
    love.graphics.pop()
end

return Stars
