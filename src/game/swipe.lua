-- A melee arc. One instance per attacker: swing() starts a sweep, update()
-- advances it and resolves each target at most once per swing. There is no
-- blade sprite -- the weapon *is* the tapering additive arc plus the sparks it
-- throws off, which is also why the shape is all constants rather than art.

local Palette = require "game.palette"
local Particles = require "particles"
local Math = require "utils.math"

local Swipe = {}
Swipe.__index = Swipe

local ARC = math.pi * 0.8 -- how wide the sweep is
local INNER = 14          -- world units; the arc starts outside the body, not at its centre
local REACH = 54          -- ...and ends here, which is what the hit test uses
local DURATION = 0.16     -- time the blade takes to cross the arc
local AFTERGLOW = 0.10    -- the trail lingers this long after it lands
local COOLDOWN = 0.30
local SEGMENTS = 16       -- spokes the blur is drawn with
local SPARK_INTERVAL = 0.012
local SPARK_SCALE = 0.6
local EDGE_WIDTH = 4
local TIP_RADIUS = 4

-- exported for the debug overlay, which draws the reach it can't otherwise know
Swipe.ARC, Swipe.REACH = ARC, REACH

-- shortest signed distance from `from` to `to`, in (-pi, pi]
local function angleDelta(to, from)
    return (to - from + math.pi) % (math.pi * 2) - math.pi
end

function Swipe.new(config)
    config = config or {}
    return setmetatable({
        damage = config.damage or 1,
        knockback = config.knockback or 280,
        -- the knockback has a height component now that there is one; a hit
        -- pops its target a third of a tile up rather than only sliding it
        lift = config.lift or 130,
        sparks = Particles.Burst.new{
            countMin = 2, countMax = 4,
            sizeMin = 0.6, sizeMax = 1.8,
            speedMin = 30, speedMax = 140,
            lifeMin = 0.12, lifeMax = 0.32,
            drag = 7,
        },
        impact = Particles.Burst.new{
            countMin = 10, countMax = 16,
            sizeMin = 1.0, sizeMax = 2.8,
            speedMin = 90, speedMax = 280,
            lifeMin = 0.20, lifeMax = 0.50,
            drag = 5,
        },
        x = 0, y = 0, drawY = 0,
        angle = 0,
        dir = 1, -- flips per swing, so consecutive swings mirror instead of repeating
        active = false,
        t = 0,
        cooldown = 0,
        sparkTimer = 0,
        hit = {}, -- target -> true, cleared per swing
    }, Swipe)
end

function Swipe:ready()
    return self.cooldown <= 0 and not self.active
end

function Swipe:swing(angle)
    if not self:ready() then return false end
    self.angle = angle
    self.dir = -self.dir
    self.active = true
    self.t = 0
    self.cooldown = COOLDOWN
    self.sparkTimer = 0
    for target in pairs(self.hit) do self.hit[target] = nil end
    return true
end

-- 0 at the start of the sweep, 1 once the blade has crossed the whole arc
function Swipe:progress()
    return math.min(1, self.t / DURATION)
end

-- the blade's offset from self.angle, in sweep-local terms: -ARC/2 to +ARC/2
local function bladeOffset(progress)
    return ARC * (progress - 0.5)
end

function Swipe:bladeAngle()
    return self.angle + self.dir * bladeOffset(self:progress())
end

-- a target is hit the frame the leading edge reaches it, so a swing sweeps
-- across a crowd rather than resolving all of it at once
function Swipe:resolve(targets, progress)
    if not targets then return end
    local blade = bladeOffset(progress)
    local half = ARC / 2

    for _, target in ipairs(targets) do
        if not target.dead and not self.hit[target] then
            local dx, dy = target.x - self.x, target.y - self.y
            local distance = Math.length(dx, dy)
            if distance <= REACH + target.radius then
                -- widen the window by the target's own angular size, or a small
                -- body at full reach slips between two frames of the sweep
                local slack = math.atan(target.radius / math.max(distance, 1))
                local offset = angleDelta(math.atan2(dy, dx), self.angle) * self.dir
                if offset >= -half - slack and offset <= blade + slack then
                    self.hit[target] = true
                    local nx, ny = dx / math.max(distance, 0.001), dy / math.max(distance, 0.001)
                    target:damage(self.damage, nx * self.knockback, ny * self.knockback, self.lift)

                    -- struck on the blade, so the sparks fly at the blade's
                    -- height rather than off the ground under it
                    local reach = distance - target.radius
                    self.impact:spawn(self.x + nx * reach, self.drawY + ny * reach, Palette.blade)
                end
            end
        end
    end
end

function Swipe:emitSparks(dt, progress)
    if progress >= 1 then return end
    self.sparkTimer = self.sparkTimer + dt
    while self.sparkTimer >= SPARK_INTERVAL do
        self.sparkTimer = self.sparkTimer - SPARK_INTERVAL
        local angle = self.angle + self.dir * bladeOffset(progress)
        local sparkX, sparkY = Math.polar(self.x, self.drawY, angle,
            Math.randRange(INNER, REACH))
        self.sparks:spawn(sparkX, sparkY, Palette.blade, SPARK_SCALE)
    end
end

-- the attacker is passed whole so a swing started mid-run travels with them --
-- and so the blade can be painted at the body's height while the hit test it
-- resolves stays on the ground plane, where every other distance is measured
function Swipe:update(dt, owner, targets)
    self.x, self.y = owner.x, owner.y
    self.drawY = owner:drawY()
    self.cooldown = math.max(0, self.cooldown - dt)
    self.sparks:update(dt)
    self.impact:update(dt)

    if not self.active then return end

    self.t = self.t + dt
    local progress = self:progress()
    self:resolve(targets, progress)
    self:emitSparks(dt, progress)

    if self.t >= DURATION + AFTERGLOW then self.active = false end
end

-- one spoke of the blade, from the inner radius out to the tip
function Swipe:bladeLine(angle, width, alpha)
    local innerX, innerY = Math.polar(self.x, self.drawY, angle, INNER)
    local tipX, tipY = Math.polar(self.x, self.drawY, angle, REACH)

    love.graphics.setLineWidth(width)
    love.graphics.setColor(Palette.blade[1], Palette.blade[2], Palette.blade[3], alpha)
    love.graphics.line(innerX, innerY, tipX, tipY)
    return tipX, tipY
end

function Swipe:draw()
    if self.active then
        local progress = self:progress()
        local past = self.t - DURATION
        local fade = past <= 0 and 1 or math.max(0, 1 - past / AFTERGLOW)
        local tail, blade = -ARC / 2, bladeOffset(progress)

        love.graphics.setBlendMode("add")

        -- spokes across the swept band read as motion blur; the ramp puts the
        -- brightness at the leading edge where the blade actually is
        for i = 0, SEGMENTS do
            local k = i / SEGMENTS
            self:bladeLine(self.angle + self.dir * (tail + (blade - tail) * k),
                1 + 2 * k, fade * k * k * 0.45)
        end

        local tipX, tipY = self:bladeLine(self.angle + self.dir * blade,
            EDGE_WIDTH, fade * 0.9)
        love.graphics.circle("fill", tipX, tipY, TIP_RADIUS * fade)

        love.graphics.setLineWidth(1)
        love.graphics.setBlendMode("alpha")
        love.graphics.setColor(1, 1, 1, 1)
    end

    self.sparks:draw()
    self.impact:draw()
end

return Swipe
