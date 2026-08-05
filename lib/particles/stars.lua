-- lib/particles/stars.lua
-- The fixed night sky behind the loading screen and the menu: a field of
-- twinkling points plus a few constellations linking some of them.

local Theme = require "lib.ui.theme"
local Math = require "lib.utils.math"

local Stars = {}
Stars.__index = Stars

function Stars.new(config)
    config = config or {}
    return setmetatable({
        stars = {},
        -- One flat {x, y, x, y, ...} polyline per constellation, since a
        -- constellation's stars are consecutive by construction.
        chains = {},
        -- Per-star {x, y, r, g, b, a} entries for one batched points() call.
        -- Built once by buildBatches and rewritten in place each frame.
        points = {},
        amountMin = config.amountMin or 150,
        amountMax = config.amountMax or 190,
        brightnessOscillation = config.brightnessOscillation or 0.7,
        blinkSpeedMin = config.blinkSpeedMin or 0.3,
        blinkSpeedMax = config.blinkSpeedMax or 1.2,
        constellationCountMin = config.constellationCountMin or 3,
        constellationCountMax = config.constellationCountMax or 6,
        constellationStarsMin = config.constellationStarsMin or 6,
        constellationStarsMax = config.constellationStarsMax or 10,
        -- Max distance a constellation "walks" between consecutive stars.
        constellationSpread = config.constellationSpread or 160,
        -- Max heading change per step; smaller = smoother, more flowing chains.
        constellationTurn = config.constellationTurn or math.pi / 3,
        lineAlpha = config.lineAlpha or 0.2,
        -- Global opacity multiplier, so a screen can fade the whole sky in or
        -- out without touching the per-star brightness the twinkle drives.
        alpha = config.alpha or 1,
    }, Stars)
end

local function newStar(x, y, blinkSpeedMin, blinkSpeedMax, brightnessMin, brightnessMax)
    return {
        x = x,
        y = y,
        brightness = Math.randRange(brightnessMin, brightnessMax),
        blinkPhase = Math.randAngle(),
        blinkSpeed = Math.randRange(blinkSpeedMin, blinkSpeedMax),
    }
end

-- Random-walks a chain of stars across the screen and links each consecutive
-- pair. The walk keeps a heading and only turns gently each step, so the chain
-- flows like a real constellation instead of scribbling back over itself, and
-- it reflects off the screen edges rather than piling stars up on the border.
function Stars:spawnConstellation(w, h)
    local starCount = Math.randInt(self.constellationStarsMin, self.constellationStarsMax)
    -- Start away from the edges so the chain has room to spread out.
    local margin = math.min(self.constellationSpread, math.min(w, h) / 3)
    local x = Math.randRange(margin, math.max(margin, w - margin))
    local y = Math.randRange(margin, math.max(margin, h - margin))
    local heading = Math.randAngle()
    local chain = {}

    for _ = 1, starCount do
        -- Constellation stars read brighter than the scattered background ones.
        local star = newStar(x, y, self.blinkSpeedMin, self.blinkSpeedMax, 0.85, 1.0)
        self.stars[#self.stars + 1] = star

        chain[#chain + 1] = star.x
        chain[#chain + 1] = star.y

        -- Turn only gently from the current heading, and keep the step lengths
        -- fairly close together so consecutive stars stay visibly linked.
        heading = heading + Math.randRange(-self.constellationTurn, self.constellationTurn)
        local dist = Math.randRange(self.constellationSpread * 0.55, self.constellationSpread)
        local nx = x + math.cos(heading) * dist
        local ny = y + math.sin(heading) * dist

        -- Reflect the heading off whichever edge the next step would cross so
        -- the chain turns back inward instead of stacking on the border.
        if nx < margin or nx > w - margin then heading = math.pi - heading end
        if ny < margin or ny > h - margin then heading = -heading end
        x = Math.clamp(x + math.cos(heading) * dist, 0, w)
        y = Math.clamp(y + math.sin(heading) * dist, 0, h)
    end

    -- love.graphics.line needs at least two points to draw anything.
    if #chain >= 4 then
        self.chains[#self.chains + 1] = chain
    end
end

function Stars:spawnStars()
    -- Deliberately a fixed 1920x1080 space rather than the window: it is the
    -- largest supported resolution, so the sky never has to be regenerated when
    -- the player changes resolution — the window is just a viewport onto it.
    local w, h = 1920, 1080
    self.stars = {}
    self.chains = {}

    for _ = 1, Math.randInt(self.amountMin, self.amountMax) do
        self.stars[#self.stars + 1] = newStar(Math.randRange(0, w), Math.randRange(0, h),
            self.blinkSpeedMin, self.blinkSpeedMax, 0.6, 1.0)
    end

    for _ = 1, Math.randInt(self.constellationCountMin, self.constellationCountMax) do
        self:spawnConstellation(w, h)
    end

    self:buildBatches()
end

-- Bakes the static half of the draw: star positions never move, so a frame only
-- has to rewrite each point's colour (see draw). Stars outside a smaller window
-- are kept rather than culled — culling was measured and made no difference.
function Stars:buildBatches()
    local points = {}
    for i, s in ipairs(self.stars) do
        points[i] = { s.x, s.y, 1, 1, 1, 1 }
    end
    self.points = points
end

function Stars:update(dt)
    for _, s in ipairs(self.stars) do
        s.blinkPhase = s.blinkPhase + dt * s.blinkSpeed
    end
end

function Stars:draw()
    if self.alpha <= 0 then return end

    Theme.setColor(Theme.colors.textDim, self.lineAlpha * self.alpha)
    for _, chain in ipairs(self.chains) do
        love.graphics.line(chain)
    end

    -- One points() call for the whole sky, with each star's twinkle written into
    -- its own vertex colour rather than into a setColor call of its own — this
    -- loop runs ~190 times a frame, so the Lua->C crossings are the cost here.
    local oscillation = self.brightnessOscillation
    local alpha = self.alpha
    local points = self.points
    for i, s in ipairs(self.stars) do
        local brightness = s.brightness + math.sin(s.blinkPhase) * oscillation
        if brightness < 0 then brightness = 0 elseif brightness > 1 then brightness = 1 end
        local p = points[i]
        p[3], p[4], p[5], p[6] = brightness, brightness, brightness, alpha
    end

    local prevSize = love.graphics.getPointSize()
    love.graphics.setPointSize(2)
    -- Per-point colours are multiplied by the draw colour, so the theme's star
    -- tint applies to the whole sky at once (and overrides what the
    -- constellation pass left behind).
    Theme.setColor(Theme.colors.star, 1)
    love.graphics.points(points)
    love.graphics.setPointSize(prevSize)
end

return Stars
