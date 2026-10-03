--- Entity mixin: steering, turning and staying inside the world.

local Math = require("utils.math")

local Movement = {}

--- unit direction to walk, or zero
function Movement:setMove(dx, dy)
    local len = Math.length(dx, dy)
    if len > 0 then
        self.moveX, self.moveY = dx / len, dy / len
    else
        self.moveX, self.moveY = 0, 0
    end
end

--- eases velocity toward moveX/moveY at `speed`
---@param dt number
function Movement:steer(dt)
    local moving = self.moveX ~= 0 or self.moveY ~= 0
    local t = 1 - Math.decay(moving and self.accel or self.decel, dt)
    self.vx = self.vx + (self.moveX * self.speed - self.vx) * t
    self.vy = self.vy + (self.moveY * self.speed - self.vy) * t
end

--- turns toward where it walks; holds while standing
---@param dt number
function Movement:turn(dt)
    if self.moveX == 0 and self.moveY == 0 then return end
    local target = math.atan2(self.moveY, self.moveX)
    local a = Math.lerpAngle(self.angle, target, 1 - Math.decay(self.turnRate, dt))
    self.angle = (a + math.pi) % (math.pi * 2) - math.pi
end

--- keeps the whole body in the world, stopping at edges
---@param world table
function Movement:clamp(world)
    local r = self.radius
    local x = Math.clamp(self.x, r, math.max(r, world.w - r))
    local y = Math.clamp(self.y, r, math.max(r, world.h - r))
    if x ~= self.x then self.vx = 0 end
    if y ~= self.y then self.vy = 0 end
    self.x, self.y = x, y
end

---@param other table
---@return number
function Movement:distanceTo(other)
    return Math.length(other.x - self.x, other.y - self.y)
end

---@param other table
---@return boolean
function Movement:overlaps(other)
    return self:distanceTo(other) < self.radius + other.radius
end

return Movement
