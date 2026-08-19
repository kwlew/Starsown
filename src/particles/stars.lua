-- Fixed night sky behind the loading screen and menu: twinkling points plus a
-- few constellations linking some of them.

local Theme = require "ui.core.theme"
local Math = require "utils.math"
local Motion = require "ui.core.motion"

local Stars = {}
Stars.__index = Stars

function Stars.new(config)
    config = config or {}
    return setmetatable({
        stars = {},
        chains = {}, -- one flat {x,y,x,y,...} polyline per constellation
        points = {}, -- per-star {x,y,r,g,b,a} for one batched points() call, rewritten each frame
        amountMin = config.amountMin or 150,
        amountMax = config.amountMax or 190,
        brightnessOscillation = config.brightnessOscillation or 0.7,
        blinkSpeedMin = config.blinkSpeedMin or 0.3,
        blinkSpeedMax = config.blinkSpeedMax or 1.2,
        constellationCountMin = config.constellationCountMin or 3,
        constellationCountMax = config.constellationCountMax or 6,
        constellationStarsMin = config.constellationStarsMin or 6,
        constellationStarsMax = config.constellationStarsMax or 10,
        constellationSpread = config.constellationSpread or 160, -- max walk distance between consecutive stars
        constellationTurn = config.constellationTurn or math.pi / 3, -- max heading change per step
        lineAlpha = config.lineAlpha or 0.2,
        alpha = config.alpha or 1, -- global fade, on top of per-star twinkle brightness
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

-- random-walks a chain of stars across the screen, linking each consecutive
-- pair; keeps a heading and turns gently each step so it flows like a real
-- constellation, and reflects off screen edges instead of piling up on the border
function Stars:spawnConstellation(w, h)
    local starCount = Math.randInt(self.constellationStarsMin, self.constellationStarsMax)
    local margin = math.min(self.constellationSpread, math.min(w, h) / 3)
    local x = Math.randRange(margin, math.max(margin, w - margin))
    local y = Math.randRange(margin, math.max(margin, h - margin))
    local heading = Math.randAngle()
    local chain = {}

    for _ = 1, starCount do
        local star = newStar(x, y, self.blinkSpeedMin, self.blinkSpeedMax, 0.85, 1.0) -- brighter than background stars
        self.stars[#self.stars + 1] = star

        chain[#chain + 1] = star.x
        chain[#chain + 1] = star.y

        heading = heading + Math.randRange(-self.constellationTurn, self.constellationTurn)
        local dist = Math.randRange(self.constellationSpread * 0.55, self.constellationSpread)
        local nx = x + math.cos(heading) * dist
        local ny = y + math.sin(heading) * dist

        -- reflect off whichever edge the next step would cross, so the chain turns back inward
        if nx < margin or nx > w - margin then heading = math.pi - heading end
        if ny < margin or ny > h - margin then heading = -heading end
        x = Math.clamp(x + math.cos(heading) * dist, 0, w)
        y = Math.clamp(y + math.sin(heading) * dist, 0, h)
    end

    if #chain >= 4 then -- love.graphics.line needs at least two points
        self.chains[#self.chains + 1] = chain
    end
end

function Stars:spawnStars()
    -- fixed 1920x1080 space, not the window: it's the largest supported
    -- resolution, so the sky never regenerates on a resolution change
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

-- static half of the draw: positions never move, so a frame only rewrites
-- color (see draw). Stars outside a smaller window aren't culled -- measured, no difference.
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

    -- one points() call for the whole sky; twinkle written into each vertex's
    -- own color instead of a setColor per star, since this runs ~190x/frame
    -- and the Lua->C crossings are the cost
    local oscillation = Motion.reduced and 0 or self.brightnessOscillation -- reduced motion: no twinkle
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
    -- per-point colors are multiplied by the draw color, so the theme's star
    -- tint applies to the whole sky at once
    Theme.setColor(Theme.colors.star, 1)
    love.graphics.points(points)
    love.graphics.setPointSize(prevSize)
end

return Stars
