local Theme = require "lib.ui.theme"

local Starfield = {}
Starfield.__index = Starfield

local function randRange(min, max)
    return min + math.random() * (max - min)
end

function Starfield.new(config)
    config = config or {}
    return setmetatable({
        stars = {},
        timer = 0,
        spawnMin = config.spawnMin or 1.0, -- seconds between spawns (min)
        spawnMax = config.spawnMax or 1.5, -- seconds between spawns (max)
        speedMin = config.speedMin or 100,
        speedMax = config.speedMax or 600,
        lengthMin = config.lengthMin or 200,
        lengthMax = config.lengthMax or 600,
        lifeMin = config.lifeMin or 1.5,
        lifeMax = config.lifeMax or 5.2,
        -- Fraction of maxLife (0..1) at which a star starts slowing down and
        -- turning red before it disappears. 0.7 = last 30% of its life.
        dyingThreshold = config.dyingThreshold or 0.7,
    }, Starfield)
end

function Starfield:spawnStar()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    -- Upper-left section: slightly off-screen top/left, drifting down-right.
    local x = randRange(-0.05 * w, 0.35 * w)
    local y = randRange(-0.05 * h, 0.35 * h)
    local angle = math.rad(randRange(42, 48)) -- down-right diagonal
    local speed = randRange(self.speedMin, self.speedMax)
    self.stars[#self.stars + 1] = {
        x = x, y = y,
        vx = math.cos(angle) * speed,
        vy = math.sin(angle) * speed,
        length = randRange(self.lengthMin, self.lengthMax),
        life = 0,
        maxLife = randRange(self.lifeMin, self.lifeMax),
    }
end

-- How far into its "dying" phase a star is: 0 before dyingThreshold of its
-- lifetime, ramping to 1 right as it expires. Drives both the slowdown and
-- the white -> red color shift so the two land together as one beat.
local function dyingFactor(s, threshold)
    local lifeRatio = s.life / s.maxLife
    if lifeRatio <= threshold then return 0 end
    return (lifeRatio - threshold) / (1 - threshold)
end

function Starfield:update(dt)
    self.timer = self.timer - dt
    if self.timer <= 0 then
        self.timer = randRange(self.spawnMin, self.spawnMax)
        self:spawnStar()
    end

    -- Iterate backwards so table.remove during the loop is safe.
    for i = #self.stars, 1, -1 do
        local s = self.stars[i]
        s.life = s.life + dt

        -- Ease down to ~15% speed near expiry instead of vanishing at full
        -- speed. Computed fresh from the life ratio each frame (not applied
        -- by shrinking s.vx in place), so the curve is frame-rate independent.
        local dying = dyingFactor(s, self.dyingThreshold)
        local speedScale = 1 - dying * 0.85

        s.x = s.x + s.vx * speedScale * dt
        s.y = s.y + s.vy * speedScale * dt

        if s.life >= s.maxLife then
            table.remove(self.stars, i)
        end
    end
end

local function drawStar(s, dyingThreshold)
    local speed = math.sqrt(s.vx * s.vx + s.vy * s.vy)
    if speed == 0 then return end
    local dx, dy = s.vx / speed, s.vy / speed -- unit direction (unaffected by slowdown)
    local nx, ny = -dy, dx                     -- perpendicular (for trail width)

    local headW, tailW = 3, 0.5
    local tailX, tailY = s.x - dx * s.length, s.y - dy * s.length
    local fade = 1 - (s.life / s.maxLife) -- 1 = fresh, 0 = about to die

    -- White -> red as it approaches expiry, for a "burning out" flash.
    local dying = dyingFactor(s, dyingThreshold)
    local r, g, b = Theme.lerp({ 1, 1, 1 }, { 1, 0.15, 0.1 }, dying)

    local vertices = {
        { s.x + nx * headW, s.y + ny * headW, 0, 0, r, g, b, fade },
        { s.x - nx * headW, s.y - ny * headW, 0, 0, r, g, b, fade },
        { tailX - nx * tailW, tailY - ny * tailW, 0, 0, r, g, b, 0 },
        { tailX + nx * tailW, tailY + ny * tailW, 0, 0, r, g, b, 0 },
    }
    local mesh = love.graphics.newMesh(vertices, "fan")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(mesh)

    Theme.glowRect(s.x - 4, s.y - 4, 8, 8, 4, fade, { r, g, b })
    love.graphics.setColor(r, g, b, fade)
    love.graphics.circle("fill", s.x, s.y, 2)
    love.graphics.setColor(1, 1, 1, 1)
end

function Starfield:draw()
    for _, s in ipairs(self.stars) do
        drawStar(s, self.dyingThreshold)
    end
end

return Starfield