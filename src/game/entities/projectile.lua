--- A thrown object: straight, spinning, spent on first hit.

local Entity = require("game.entity")

local Projectile = Entity:extend{
    name = "projectile",
    kind = "projectile",
    radius = 6,
    solid = false,
    deathEffect = false,
    maxHealth = 1,
    invulnerableTime = 0,
    spriteAngle = 0,
    facesMovement = false,
    fallbackColor = "danger",
    targetKind = "player",
    hitDamage = 1,
    knockbackForce = 200,
    flySpeed = 320,
    range = 420, -- design px before it's spent
    spin = 14,   -- radians per second
}

---@param opts table # { angle, owner?, flySpeed?, hitDamage?, range? }
function Projectile:init(opts)
    self.owner = opts.owner
    self.flySpeed = opts.flySpeed or self.flySpeed
    self.hitDamage = opts.hitDamage or self.hitDamage
    self.range = opts.range or self.range
    self.travelled = 0
    self.vx, self.vy = math.cos(opts.angle) * self.flySpeed, math.sin(opts.angle) * self.flySpeed
    self.angle, self.prevAngle = opts.angle, opts.angle
end

---@return boolean
function Projectile:outOfBounds(world)
    return self.travelled >= self.range or self.x < 0 or self.y < 0 or self.x > world.w or self.y > world.h
end

--- the first target touched takes the hit
function Projectile:hitSomething(world)
    for target in world:each(self.targetKind) do
        if self:overlaps(target) then
            if target:damage(self.hitDamage, self.owner or self) then
                target:knockback(self.x - self.vx, self.y - self.vy, self.knockbackForce)
            end
            return true
        end
    end
    return false
end

--- straight flight; nothing steers or clamps
function Projectile:tick(dt, world)
    self.prevX, self.prevY, self.prevAngle = self.x, self.y, self.angle
    self.x, self.y = self.x + self.vx * dt, self.y + self.vy * dt
    self.angle = self.angle + self.spin * dt
    self.travelled = self.travelled + self.flySpeed * dt
    if self:outOfBounds(world) or self:hitSomething(world) then self:remove() end
end

return Projectile
