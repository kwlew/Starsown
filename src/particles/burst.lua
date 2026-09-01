-- Short-lived radial particle explosions. One Burst instance owns a pool and
-- can be fired repeatedly:
--
--   self.burst = Burst.new{}
--   self.burst:spawn(x, y, { 1, 0.4, 0.2 })
--   function State:update(dt) self.burst:update(dt) end
--   function State:draw()     self.burst:draw()     end

local Math = require "utils.math"

local Burst = {}
Burst.__index = Burst

function Burst.new(config)
    config = config or {}
    return setmetatable({
        particles = {},
        spent = {}, -- pool of dead particles, reused instead of reallocated
        countMin = config.countMin or 14,
        countMax = config.countMax or 22,
        speedMin = config.speedMin or 60,
        speedMax = config.speedMax or 260,
        lifeMin = config.lifeMin or 0.35,
        lifeMax = config.lifeMax or 0.9,
        sizeMin = config.sizeMin or 1.5,
        sizeMax = config.sizeMax or 3.5,
        drag = config.drag or 3.5, -- exponential velocity decay
    }, Burst)
end

-- color is {r,g,b} (default white); scale multiplies speed and size
function Burst:spawn(x, y, color, scale)
    color = color or { 1, 1, 1 }
    scale = scale or 1
    local spent = self.spent

    for _ = 1, Math.randInt(self.countMin, self.countMax) do
        local angle = Math.randAngle()
        local speed = Math.randRange(self.speedMin, self.speedMax) * scale

        local p = spent[#spent]
        if p then spent[#spent] = nil else p = {} end

        p.x, p.y = x, y
        p.vx = math.cos(angle) * speed
        p.vy = math.sin(angle) * speed
        p.life = 0
        p.maxLife = Math.randRange(self.lifeMin, self.lifeMax)
        p.size = Math.randRange(self.sizeMin, self.sizeMax) * scale
        p.r, p.g, p.b = color[1], color[2], color[3]

        self.particles[#self.particles + 1] = p
    end
end

function Burst:update(dt)
    local decay = Math.decay(self.drag, dt)

    -- compact in one forward pass; table.remove in a reverse loop was
    -- quadratic since a whole burst tends to expire together
    local kept = 0
    for i = 1, #self.particles do
        local p = self.particles[i]
        p.life = p.life + dt

        if p.life >= p.maxLife then
            self.spent[#self.spent + 1] = p
        else
            p.vx = p.vx * decay
            p.vy = p.vy * decay
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            kept = kept + 1
            self.particles[kept] = p
        end
    end
    for i = #self.particles, kept + 1, -1 do
        self.particles[i] = nil
    end
end

function Burst:draw()
    if #self.particles == 0 then return end -- most bursts idle most of the time

    love.graphics.setBlendMode("add") -- overlapping debris glows hot at the center
    for _, p in ipairs(self.particles) do
        local t = 1 - p.life / p.maxLife -- 1 = fresh, 0 = gone
        love.graphics.setColor(p.r, p.g, p.b, t)
        love.graphics.circle("fill", p.x, p.y, p.size * t, 8) -- low segment count, only a few px across
    end
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(1, 1, 1, 1)
end

return Burst
