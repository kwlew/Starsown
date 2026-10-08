--- What shooting stars shed: burn-out embers, glitter behind specials, crumbs of popped trails.

local Burst = require("particles.burst")
local Look = require("particles.starfield.look")
local Math = require("utils.math")

local Debris = {}
Debris.__index = Debris

local GLITTER_INTERVAL = 0.035 -- s between motes behind a special
local GLITTER_JITTER = 2.5     -- px off the head
local GLITTER_LAG = 0.15       -- of the star's motion the motes keep
local CRUMB_SPACING = 7        -- px of trail per crumb
local CRUMB_MAX = 70
local CRUMB_CARRY = 25         -- px/s along the star's path

local scratch = {} -- reused colour; Burst copies it out

local EMBERS = {
    countMin = 4, countMax = 7,
    speedMin = 14, speedMax = 60,
    lifeMin = 0.25, lifeMax = 0.55,
    sizeMin = 1, sizeMax = 2,
    drag = 5,
    gravity = 18,
    hot = 0.3,
    glow = 3,
    twinkle = 0.6,
}
local GLITTER = {
    speedMin = 5, speedMax = 25,
    lifeMin = 0.5, lifeMax = 1.1,
    sizeMin = 0.6, sizeMax = 1.3,
    drag = 3,
    gravity = 16,
    hot = 0.3,
    glow = 3,
    twinkle = 0.85,
}
local CRUMBS = {
    speedMin = 4, speedMax = 24,
    lifeMin = 0.4, lifeMax = 1.0,
    sizeMin = 0.6, sizeMax = 1.4,
    drag = 2,
    gravity = 14,
    glow = 2.5,
    twinkle = 0.5,
}

---@param config? table # `embers` overrides its Burst config
---@return table
function Debris.new(config)
    config = config or {}
    return setmetatable({
        embers = Burst.new(Burst.merged(EMBERS, config.embers)),
        glitter = Burst.new(GLITTER),
        crumbs = Burst.new(CRUMBS),
    }, Debris)
end

---@param k number # brightness; additive light just dims
---@return number[] RGB
local function dimmed(r, g, b, k)
    scratch[1], scratch[2], scratch[3] = r * k, g * k, b * k
    return scratch
end

--- a puff where a star burnt out
---@param s table
---@param speed number # its current px/s
function Debris:ember(s, speed)
    local flare = dimmed(s.flare[1], s.flare[2], s.flare[3], s.brightness)
    self.embers:spawn(s.x, s.y, flare, s.scale * ((s.golden or s.rainbow) and 2 or 1),
        s.dirX * speed * 0.3, s.dirY * speed * 0.3)
end

--- twinkling motes left behind the head, at a steady rate
---@param s table
---@param dt number
---@param speed number # its current px/s
---@param fade number # 0..1; a dying star sheds less
function Debris:shed(s, dt, speed, fade, r, g, b)
    s.shedTimer = (s.shedTimer or 0) + dt
    while s.shedTimer >= GLITTER_INTERVAL do
        s.shedTimer = s.shedTimer - GLITTER_INTERVAL
        if math.random() < fade then
            local x = s.x + Math.randRange(-GLITTER_JITTER, GLITTER_JITTER)
            local y = s.y + Math.randRange(-GLITTER_JITTER, GLITTER_JITTER)
            self.glitter:emit(x, y, Math.randAngle(), dimmed(r, g, b, 1), s.scale * 0.7,
                s.dirX * speed * GLITTER_LAG, s.dirY * speed * GLITTER_LAG)
        end
    end
end

--- a popped trail breaks into dust, thinning toward the tail
---@param s table
---@param length number # px of trail on screen
function Debris:crumble(s, length, r, g, b)
    local count = math.min(CRUMB_MAX, math.floor(length / CRUMB_SPACING))
    for i = 0, count do
        local t = i / math.max(count, 1)
        if math.random() < 1 - t * 0.7 then
            if s.rainbow then r, g, b = Look.trailHue(s, t) end
            local color = dimmed(r, g, b, s.brightness)
            self.crumbs:emit(s.x - s.dirX * length * t, s.y - s.dirY * length * t, Math.randAngle(),
                color, s.scale * (1 - t * 0.5), s.dirX * CRUMB_CARRY, s.dirY * CRUMB_CARRY)
        end
    end
end

---@param dt number
function Debris:update(dt)
    self.embers:update(dt)
    self.glitter:update(dt)
    self.crumbs:update(dt)
end

--- inside the starfield's additive pass
function Debris:draw()
    self.crumbs:draw(true)
    self.glitter:draw(true)
    self.embers:draw(true)
end

return Debris
