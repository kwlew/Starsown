local Theme = require "lib.ui.theme"
local Math = require "lib.utils.math"

local Stars = {}
Stars.__index = Stars

function Stars.new(config)
    config = config or {}
    return setmetatable({
        stars = {},
        -- Constellations are stored as polylines (flat {x, y, x, y, ...}), not
        -- as edge pairs: the stars in one are consecutive by construction, so a
        -- single love.graphics.line draws exactly the same segments the old
        -- per-edge loop did.
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
        blinkPhase = Math.randRange(0, 2 * math.pi),
        blinkSpeed = Math.randRange(blinkSpeedMin, blinkSpeedMax),
    }
end

-- Random-walks a chain of stars across the screen and links each consecutive
-- pair. The walk keeps a heading and only turns gently each step, so the chain
-- flows like a real constellation instead of scribbling back over itself, and
-- it reflects off the screen edges rather than piling stars up on the border.
function Stars:spawnConstellation(w, h)
    local starCount = math.floor(Math.randRange(self.constellationStarsMin, self.constellationStarsMax + 1))
    -- Start away from the edges so the chain has room to spread out.
    local margin = math.min(self.constellationSpread, math.min(w, h) / 3)
    local x = Math.randRange(margin, math.max(margin, w - margin))
    local y = Math.randRange(margin, math.max(margin, h - margin))
    local heading = Math.randRange(0, 2 * math.pi)
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
        x = math.max(0, math.min(w, x + math.cos(heading) * dist))
        y = math.max(0, math.min(h, y + math.sin(heading) * dist))
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

    local amount = Math.randRange(self.amountMin, self.amountMax)
    for _ = 1, amount do
        self.stars[#self.stars + 1] = newStar(Math.randRange(0, w), Math.randRange(0, h),
            self.blinkSpeedMin, self.blinkSpeedMax, 0.6, 1.0)
    end

    local constellationCount = math.floor(Math.randRange(self.constellationCountMin, self.constellationCountMax + 1))
    for _ = 1, constellationCount do
        self:spawnConstellation(w, h)
    end

    self:buildBatches()
end

-- Bakes the static half of the draw: star positions never move, so a frame only
-- has to rewrite each point's colour (see draw).
--
-- Off-screen stars are deliberately kept in the buffer. The sky lives in a fixed
-- 1920x1080 space, so a smaller window leaves some outside it — but culling them
-- was measured and made no difference: the per-frame cost splits about evenly
-- between the constellation polylines, this loop, and the points() call itself,
-- and skipping entries only touches the last two. It cost a free-list and a
-- contiguity invariant for nothing.
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

    -- One polyline per constellation rather than one call per edge.
    local c = Theme.colors.textDim
    love.graphics.setColor(c[1], c[2], c[3], self.lineAlpha * self.alpha)
    for _, chain in ipairs(self.chains) do
        love.graphics.line(chain)
    end

    -- One points() call for the whole sky, with each star's twinkle written
    -- into its own vertex colour. This was a setColor + points pair per star:
    -- ~380 Lua->C crossings a frame for a background that never moves. LOVE's
    -- auto-batcher already collapsed the GPU side, so the win here is CPU.
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
    -- White: per-point colours are multiplied by the current draw colour, which
    -- the constellation pass above left tinted.
    love.graphics.setColor(0.65, 0.75, 1, 1)
    love.graphics.points(points)
    love.graphics.setPointSize(prevSize)
end

return Stars
