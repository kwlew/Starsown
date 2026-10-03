--- Entity mixin: damage, healing, knockback and dying.

local DeathEffect = require("game.deathEffect")
local Math = require("utils.math")
local UI = require("ui")

local Health = {}

---@param amount number
---@param source? table
---@return boolean # it landed; not while dead or invulnerable
function Health:damage(amount, source)
    if not self.alive or amount <= 0 or self.invulnerable > 0 then return false end
    self.health = math.max(0, self.health - amount)
    self.invulnerable = self.invulnerableTime
    if self.health == 0 then self:kill() end
    return true
end

---@param amount number
function Health:heal(amount)
    if self.alive then self.health = math.min(self.maxHealth, self.health + amount) end
end

--- an impulse away from a point; steering eases it out
---@param strength number # design px per second
function Health:knockback(fromX, fromY, strength)
    local dx, dy = self.x - fromX, self.y - fromY
    local len = Math.length(dx, dy)
    if len == 0 then dx, dy, len = math.cos(self.angle), math.sin(self.angle), 1 end
    self.vx = self.vx + dx / len * strength
    self.vy = self.vy + dy / len * strength
end

function Health:kill()
    if not self.alive then return end
    if self.deathEffect and self.world then self.world:addEffect(DeathEffect.new(self)) end
    self:remove()
end

--- leaves the world at the end of this step
function Health:remove()
    self.alive = false
end

--- flickers while invulnerable; steady under reduced motion
---@return number # 0..1
function Health:hurtAlpha()
    if self.invulnerable <= 0 then return 1 end
    if UI.Motion.reduced then return 0.5 end
    return math.floor(self.invulnerable * 12) % 2 == 0 and 0.35 or 1
end

return Health
