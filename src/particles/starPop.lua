--- A shooting star bursting: flash, hot sparks, then drifting glitter.
--
--   local pop = StarPop.new()
--   pop:spawn(x, y, { color = c, vx = vx, vy = vy, golden = true })

local Burst = require("particles.burst")
local Ease = require("utils.ease")
local Math = require("utils.math")
local Motion = require("ui.core.motion")
local Textures = require("particles.textures")

local StarPop = {}
StarPop.__index = StarPop

local TEXTURE = Textures.SIZE

local FLASH_LIFE = 0.16
local FLASH_RADIUS = 22
local GLINT_LIFE = 1     -- golden and rainbow only
local GLINT_LENGTH = 70
local GLINT_SPIN = 1.2  -- rad/s
local INHERIT = 0.7     -- of the star's motion carried into the debris
local SPECIAL_DUST = 2  -- extra glitter for golden and rainbow

local scratch = {} -- reused colour; Burst copies it out

local SPARKS = {
    countMin = 14, countMax = 22,
    sizeMin = 0.8, sizeMax = 1.8,
    speedMin = 140, speedMax = 380,
    lifeMin = 0.18, lifeMax = 0.42,
    drag = 7,
    streak = 0.035,
    hot = 0.45,
    glow = 2.5,
}
local DUST = {
    countMin = 10, countMax = 18,
    sizeMin = 0.6, sizeMax = 1.6,
    speedMin = 15, speedMax = 90,
    lifeMin = 0.6, lifeMax = 1.3,
    drag = 2.5,
    gravity = 22,
    hot = 0.2,
    glow = 3,
    twinkle = 0.8,
}

---@param config? table # `sparks`, `dust` override the Burst configs
---@return table
function StarPop.new(config)
    config = config or {}
    return setmetatable({
        sparks = Burst.new(Burst.merged(SPARKS, config.sparks)),
        dust = Burst.new(Burst.merged(DUST, config.dust)),
        flashes = {},
    }, StarPop)
end

--- rainbow debris gets a hue each, rather than one colour
---@param burst table
---@param scale number
local function spawnRainbow(burst, x, y, scale, vx, vy)
    for _ = 1, Math.randInt(burst.countMin, burst.countMax) do
        scratch[1], scratch[2], scratch[3] = Math.Color.fromHue(math.random())
        burst:emit(x, y, Math.randAngle(), scratch, scale, vx, vy)
    end
end

---@param opts table # color, scale?, vx?, vy? (the star's motion), golden?, rainbow?
function StarPop:spawn(x, y, opts)
    local scale = opts.scale or 1
    local vx, vy = (opts.vx or 0) * INHERIT, (opts.vy or 0) * INHERIT
    local special = opts.golden or opts.rainbow
    local color = opts.color

    if opts.rainbow then
        spawnRainbow(self.sparks, x, y, scale, vx, vy)
        for _ = 1, SPECIAL_DUST do spawnRainbow(self.dust, x, y, scale, vx, vy) end
    else
        self.sparks:spawn(x, y, color, scale, vx, vy)
        for _ = 1, special and SPECIAL_DUST or 1 do self.dust:spawn(x, y, color, scale, vx, vy) end
    end

    self.flashes[#self.flashes + 1] = {
        x = x, y = y, t = 0,
        color = color,
        rainbow = opts.rainbow,
        scale = scale,
        glint = special and not Motion.reduced,
        spin = Math.randAngle(),
    }
end

---@param dt number
function StarPop:update(dt)
    self.sparks:update(dt)
    self.dust:update(dt)
    for i = #self.flashes, 1, -1 do
        local f = self.flashes[i]
        f.t = f.t + dt
        if f.t >= (f.glint and GLINT_LIFE or FLASH_LIFE) then table.remove(self.flashes, i) end
    end
end

---@return boolean
function StarPop:active()
    return #self.flashes > 0 or #self.sparks.particles > 0 or #self.dust.particles > 0
end

---@param image any
---@param radius number # px
local function sprite(image, x, y, radius, angle, stretch)
    local s = radius * 2 / TEXTURE
    love.graphics.draw(image, x, y, angle or 0, s * (stretch or 1), s, TEXTURE / 2, TEXTURE / 2)
end

---@param f table
function StarPop:drawFlash(f)
    local r, g, b = f.color[1], f.color[2], f.color[3]
    if f.rainbow then r, g, b = Math.Color.fromHue(f.t * 2) end

    if f.t < FLASH_LIFE then
        local k = f.t / FLASH_LIFE
        local radius = FLASH_RADIUS * f.scale * Ease.outCubic(k)
        love.graphics.setColor(r, g, b, (1 - k) * 0.7)
        sprite(Textures.glow(), f.x, f.y, radius * 1.6)
        love.graphics.setColor(1, 1, 1, (1 - k) ^ 2)
        sprite(Textures.glow(), f.x, f.y, radius * 0.6)
    end

    if f.glint and f.t < GLINT_LIFE then
        local k = f.t / GLINT_LIFE
        local length = GLINT_LENGTH * f.scale * (1 - k * 0.4)
        local angle = f.spin + f.t * GLINT_SPIN
        love.graphics.setColor(r, g, b, (1 - k) ^ 1.5)
        sprite(Textures.glow(), f.x, f.y, 3 * f.scale, angle, length / (6 * f.scale))
        sprite(Textures.glow(), f.x, f.y, 3 * f.scale, angle + math.pi / 2, length / (6 * f.scale))
    end
end

---@param blendOwned? boolean # the caller already set additive blending
function StarPop:draw(blendOwned)
    if not self:active() then return end
    if not blendOwned then love.graphics.setBlendMode("add") end
    for _, f in ipairs(self.flashes) do self:drawFlash(f) end
    self.dust:draw(true)
    self.sparks:draw(true)
    if not blendOwned then love.graphics.setBlendMode("alpha") end
    love.graphics.setColor(1, 1, 1, 1)
end

return StarPop
