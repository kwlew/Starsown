--- A pooled radial particle explosion, fired as often as needed.
--
--   local burst = Burst.new{ streak = 0.03, hot = 0.3, glow = 3 }
--   burst:spawn(x, y, { 1, 0.4, 0.2 })

local Math = require("utils.math")
local Textures = require("particles.textures")

local Burst = {}
Burst.__index = Burst

local TEXTURE = Textures.SIZE
local GLOW_ALPHA = 0.35
local TWINKLE_SPEED_MIN, TWINKLE_SPEED_MAX = 14, 26

--- copy of `base` with `override`'s keys on top
---@param base table
---@param override? table
---@return table
function Burst.merged(base, override)
    local out = {}
    for key, value in pairs(base) do out[key] = value end
    for key, value in pairs(override or {}) do out[key] = value end
    return out
end

---@param config? table # count/speed/life/size min+max, drag, gravity, additive, fade,
--   streak (s of travel stretched behind), hot (life spent cooling from white),
--   glow (halo radius, in sizes), twinkle (0..1 flicker)
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
        streak = config.streak or 0,
        hot = config.hot or 0,
        glow = config.glow or 0,
        twinkle = config.twinkle or 0,
        capacity = 0,
    }, Burst)
end

---@param angle number # radians
---@param vx? number # inherited velocity
---@param vy? number
function Burst:emit(x, y, angle, color, scale, vx, vy)
    local p = table.remove(self.spent) or {}
    local speed = Math.randRange(self.speedMin, self.speedMax) * scale
    p.x, p.y = x, y
    p.vx = math.cos(angle) * speed + (vx or 0)
    p.vy = math.sin(angle) * speed + (vy or 0)
    p.life = 0
    p.maxLife = Math.randRange(self.lifeMin, self.lifeMax)
    p.size = Math.randRange(self.sizeMin, self.sizeMax) * scale
    p.r, p.g, p.b = color[1], color[2], color[3]
    p.phase = Math.randAngle()
    p.twinkleSpeed = Math.randRange(TWINKLE_SPEED_MIN, TWINKLE_SPEED_MAX)
    self.particles[#self.particles + 1] = p
end

---@param color? number[] # RGB, default white
---@param scale? number # speed and size multiplier
---@param vx? number # inherited velocity, e.g. the source's motion
---@param vy? number
function Burst:spawn(x, y, color, scale, vx, vy)
    for _ = 1, Math.randInt(self.countMin, self.countMax) do
        self:emit(x, y, Math.randAngle(), color or { 1, 1, 1 }, scale or 1, vx, vy)
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

--- grows both batches to fit every live particle, then clears them
function Burst:prepare()
    local needed = #self.particles
    if self.capacity < needed then
        self.capacity = math.max(needed, self.capacity * 2, 32)
        self.cores = love.graphics.newSpriteBatch(Textures.dot(), self.capacity, "stream")
        if self.glow > 0 then
            self.glows = love.graphics.newSpriteBatch(Textures.glow(), self.capacity, "stream")
        end
    end
    self.cores:clear()
    if self.glows then self.glows:clear() end
end

--- white-hot at birth, cooling into its own colour
---@param p table
---@return number r
---@return number g
---@return number b
function Burst:colorOf(p)
    if self.hot <= 0 then return p.r, p.g, p.b end
    local k = math.min(1, p.life / (p.maxLife * self.hot))
    return 1 + (p.r - 1) * k, 1 + (p.g - 1) * k, 1 + (p.b - 1) * k
end

---@param p table
function Burst:queue(p)
    local t = 1 - p.life / p.maxLife
    local solid = self.fade < 1
    local alpha = solid and math.min(1, t / self.fade) or t
    if self.twinkle > 0 then
        alpha = alpha * (1 - self.twinkle * (0.5 + 0.5 * math.sin(p.phase + p.life * p.twinkleSpeed)))
    end
    local radius = p.size * (solid and 0.55 + 0.45 * t or t)
    local r, g, b = self:colorOf(p)

    local width, length, angle = radius * 2, radius * 2, 0
    if self.streak > 0 then
        local speed = Math.length(p.vx, p.vy)
        length = math.max(width, speed * self.streak)
        angle = math.atan2(p.vy, p.vx)
    end
    self.cores:setColor(r, g, b, alpha)
    self.cores:add(p.x, p.y, angle, length / TEXTURE, width / TEXTURE, TEXTURE / 2, TEXTURE / 2)

    if self.glows then
        local halo = radius * self.glow * 2 / TEXTURE
        self.glows:setColor(r, g, b, alpha * GLOW_ALPHA)
        self.glows:add(p.x, p.y, 0, halo, halo, TEXTURE / 2, TEXTURE / 2)
    end
end

---@param blendOwned? boolean # the caller already set the blend mode
function Burst:draw(blendOwned)
    if #self.particles == 0 then return end
    self:prepare()
    for _, p in ipairs(self.particles) do self:queue(p) end

    if not blendOwned then love.graphics.setBlendMode(self.additive and "add" or "alpha") end
    love.graphics.setColor(1, 1, 1, 1)
    if self.glows then love.graphics.draw(self.glows) end
    love.graphics.draw(self.cores)
    if not blendOwned then love.graphics.setBlendMode("alpha") end
end

return Burst
