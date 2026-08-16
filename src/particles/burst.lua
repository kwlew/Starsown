-- src/particles/burst.lua
-- Short-lived radial particle explosions. One Burst instance owns a pool of
-- particles and can be fired repeatedly:
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
        -- Spent particles, kept for reuse. A menu Burst fires when the player
        -- clicks a star and is otherwise idle, but the board fires one on every
        -- kill and every shell that lands — thousands of small tables a minute,
        -- all identical in shape, which is exactly the churn worth avoiding.
        spent = {},
        countMin = config.countMin or 14,
        countMax = config.countMax or 22,
        speedMin = config.speedMin or 60,
        speedMax = config.speedMax or 260,
        lifeMin = config.lifeMin or 0.35,
        lifeMax = config.lifeMax or 0.9,
        sizeMin = config.sizeMin or 1.5,
        sizeMax = config.sizeMax or 3.5,
        -- Exponential velocity decay: particles shoot out then coast to a stop.
        drag = config.drag or 3.5,
    }, Burst)
end

-- Fires one explosion at (x, y). `color` is {r, g, b} (defaults to white) and
-- `scale` (default 1) multiplies the burst's speed and particle size, so a
-- bigger source can throw a bigger explosion from the same instance.
function Burst:spawn(x, y, color, scale)
    color = color or { 1, 1, 1 }
    scale = scale or 1
    local spent = self.spent

    for _ = 1, Math.randInt(self.countMin, self.countMax) do
        local angle = Math.randAngle()
        local speed = Math.randRange(self.speedMin, self.speedMax) * scale

        -- Every field is written below, so a recycled particle carries nothing
        -- forward from its last burst.
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
    -- exp() decay is frame-rate independent, unlike a per-frame multiply, so
    -- the spread looks the same at any refresh rate. Hoisted: it does not vary
    -- per particle.
    local decay = math.exp(-self.drag * dt)

    -- Compacted in a single forward pass rather than with table.remove in a
    -- reverse loop: table.remove is O(n) per call, so a burst expiring together
    -- — which is the normal case, they are spawned together — was quadratic.
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
    -- An idle pool is the common case — a Burst spends most of its life waiting
    -- for something to happen, and a caller may well own several of them — so
    -- bail before touching GL state rather than toggling the blend mode twice
    -- every frame for nothing.
    if #self.particles == 0 then return end

    -- Additive so overlapping debris glows hot at the center of the blast.
    love.graphics.setBlendMode("add")
    for _, p in ipairs(self.particles) do
        local t = 1 - p.life / p.maxLife -- 1 = fresh, 0 = gone
        love.graphics.setColor(p.r, p.g, p.b, t)
        -- Explicit low segment count: these are only a few px across, so the
        -- default (radius-derived) tessellation is wasted work.
        love.graphics.circle("fill", p.x, p.y, p.size * t, 8)
    end
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(1, 1, 1, 1)
end

return Burst
