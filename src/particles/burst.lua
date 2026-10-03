--- A pooled radial particle explosion, fired as often as needed.
--
--   local burst = Burst.new{}
--   burst:spawn(x, y, { 1, 0.4, 0.2 })

local Math = require("utils.math")

local Burst = {}
Burst.__index = Burst

---@param config? table # count/speed/life/size min+max, drag, gravity, additive, fade
---@return table
function Burst.new(config)
    config = config or {}
    return setmetatable({
        particles = {},
        spent = {}, -- dead particles, reused
        countMin = config.countMin or 14,
        countMax = config.countMax or 22,
        speedMin = config.speedMin or 60,
        speedMax = config.speedMax or 260,
        lifeMin = config.lifeMin or 0.35,
        lifeMax = config.lifeMax or 0.9,
        sizeMin = config.sizeMin or 1.5,
        sizeMax = config.sizeMax or 3.5,
        drag = config.drag or 3.5,
        gravity = config.gravity or 0,
        additive = config.additive ~= false, -- light adds; matter doesn't
        fade = config.fade or 1,             -- tail of life spent fading
    }, Burst)
end

---@param angle number # radians
function Burst:emit(x, y, angle, color, scale)
    local p = table.remove(self.spent) or {}
    local speed = Math.randRange(self.speedMin, self.speedMax) * scale
    p.x, p.y = x, y
    p.vx, p.vy = math.cos(angle) * speed, math.sin(angle) * speed
    p.life = 0
    p.maxLife = Math.randRange(self.lifeMin, self.lifeMax)
    p.size = Math.randRange(self.sizeMin, self.sizeMax) * scale
    p.r, p.g, p.b = color[1], color[2], color[3]
    self.particles[#self.particles + 1] = p
end

---@param color? number[] # RGB, default white
---@param scale? number # speed and size multiplier
function Burst:spawn(x, y, color, scale)
    for _ = 1, Math.randInt(self.countMin, self.countMax) do
        self:emit(x, y, Math.randAngle(), color or { 1, 1, 1 }, scale or 1)
    end
end

--- one direction instead of all
---@param angle number # centre of the spray
---@param spread number # total cone width, radians
function Burst:spawnCone(x, y, angle, spread, color, scale)
    for _ = 1, Math.randInt(self.countMin, self.countMax) do
        self:emit(x, y, angle + Math.randRange(-spread / 2, spread / 2), color or { 1, 1, 1 }, scale or 1)
    end
end

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
            p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
            kept = kept + 1
            self.particles[kept] = p
        end
    end
    for i = #self.particles, kept + 1, -1 do self.particles[i] = nil end
end

---@param blendOwned? boolean # the caller already set the blend mode
function Burst:draw(blendOwned)
    if #self.particles == 0 then return end
    if not blendOwned then love.graphics.setBlendMode(self.additive and "add" or "alpha") end

    local solid = self.fade < 1
    for _, p in ipairs(self.particles) do
        local t = 1 - p.life / p.maxLife
        love.graphics.setColor(p.r, p.g, p.b, solid and math.min(1, t / self.fade) or t)
        love.graphics.circle("fill", p.x, p.y, p.size * (solid and 0.55 + 0.45 * t or t), 8)
    end

    if not blendOwned then
        love.graphics.setBlendMode("alpha")
        love.graphics.setColor(1, 1, 1, 1)
    end
end

return Burst
