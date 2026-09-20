--- Short-lived radial particle explosions. One Burst instance owns a pool and
-- can be fired repeatedly:
--
--   self.burst = Burst.new{}
--   self.burst:spawn(x, y, { 1, 0.4, 0.2 })
--   function State:update(dt) self.burst:update(dt) end
--   function State:draw()     self.burst:draw()     end

local Math = require "utils.math"

local Burst = {}
Burst.__index = Burst

---@param config? table # { countMin?: integer, countMax?: integer, speedMin?: number, speedMax?: number, lifeMin?: number, lifeMax?: number, sizeMin?: number, sizeMax?: number, drag?: number, gravity?: number, additive?: boolean, fade?: number }
---@return table
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
        gravity = config.gravity or 0, -- +y accel; 0 keeps the weightless puff the menu wants
        -- light (sparks, embers) adds; matter (wood chips, leaves) doesn't, since
        -- a dozen overlapping additive particles saturate to a white blob
        additive = config.additive ~= false,
        -- the tail of the life spent fading out. 1 fades from the first frame
        -- (right for light); matter wants to stay solid and go out near the end
        fade = config.fade or 1,
    }, Burst)
end

---@param angle number # radians
local function emit(self, x, y, angle, color, scale)
    local speed = Math.randRange(self.speedMin, self.speedMax) * scale
    local spent = self.spent

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

--- color is {r,g,b} (default white); scale multiplies speed and size
---@param x number
---@param y number
---@param color? number[] # RGB, defaults to white
---@param scale? number # multiplies speed and size, defaults to 1
function Burst:spawn(x, y, color, scale)
    color = color or { 1, 1, 1 }
    for _ = 1, Math.randInt(self.countMin, self.countMax) do
        emit(self, x, y, Math.randAngle(), color, scale or 1)
    end
end

--- the same burst thrown one way instead of all ways: chips off the struck
-- face, sparks along a swing
---@param angle number # radians, the middle of the spray
---@param spread number # radians of total cone width
function Burst:spawnCone(x, y, angle, spread, color, scale)
    color = color or { 1, 1, 1 }
    for _ = 1, Math.randInt(self.countMin, self.countMax) do
        emit(self, x, y, angle + Math.randRange(-spread / 2, spread / 2), color, scale or 1)
    end
end

--- ages every particle and compacts the live ones to the front of the list,
-- moving the dead onto the pool rather than freeing them
---@param dt number
function Burst:update(dt)
    local decay = Math.decay(self.drag, dt)

    local kept = 0
    for i = 1, #self.particles do
        local p = self.particles[i]
        p.life = p.life + dt

        if p.life >= p.maxLife then
            self.spent[#self.spent + 1] = p
        else
            p.vx = p.vx * decay
            p.vy = p.vy * decay + self.gravity * dt
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

--- a no-op while the pool is idle -- which is most frames
---@param blendOwned? boolean # the caller has already set the blend mode this pool
-- wants, so this leaves the blend mode and colour alone
function Burst:draw(blendOwned)
    if #self.particles == 0 then return end -- most bursts idle most of the time

    if not blendOwned then love.graphics.setBlendMode(self.additive and "add" or "alpha") end
    local solid = self.fade < 1
    for _, p in ipairs(self.particles) do
        local t = 1 - p.life / p.maxLife -- 1 = fresh, 0 = gone
        love.graphics.setColor(p.r, p.g, p.b, solid and math.min(1, t / self.fade) or t)
        -- low segment count, only a few px across; matter keeps most of its size
        love.graphics.circle("fill", p.x, p.y, p.size * (solid and 0.55 + 0.45 * t or t), 8)
    end
    if not blendOwned then
        love.graphics.setBlendMode("alpha")
        love.graphics.setColor(1, 1, 1, 1)
    end
end

return Burst
