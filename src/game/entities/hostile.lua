--- Creatures that wander until a player is near, then attack.

local Behaviors = require("game.behaviors")
local Entity = require("game.entity")

local Hostile = Entity:extend{
    name = "hostile",
    kind = "hostile",
    maxSpeed = 100,
    maxHealth = 6,
    aggroRange = nil,     -- nil never chases
    attackDamage = 1,
    attackReach = 6,      -- design px past touching
    attackCooldown = 1,
    attackKnockback = 320,
    fallbackColor = "danger",
}

function Hostile:init()
    self.attackTimer = 0
end

function Hostile:think(dt, world)
    self.attackTimer = math.max(0, self.attackTimer - dt)
    self.target = self.aggroRange and world:nearest(self.x, self.y, "player", self.aggroRange)
    if self.target then
        self:engage(self.target, dt, world)
    else
        Behaviors.wander(self, dt)
    end
end

--- tactics with a player in range; types override
function Hostile:engage(target, dt, world)
    Behaviors.chase(self, target)
    self:tryAttack(target)
end

---@param target table
function Hostile:tryAttack(target)
    if self.attackTimer > 0 then return end
    if self:distanceTo(target) > self.radius + target.radius + self.attackReach then return end
    if target:damage(self.attackDamage, self) then
        target:knockback(self.x, self.y, self.attackKnockback)
        self.attackTimer = self.attackCooldown
    end
end

return Hostile
