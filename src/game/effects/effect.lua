--- Base for one-shot world effects: a few bursts updated and drawn together
-- in design px, done once they're all empty.
--
--   local Puff = Effect.extend{}
--   function Puff.new(x, y) local self = Effect.init(setmetatable({}, Puff), { burst }) ... end

local Tile = require("game.tile")

local Effect = {}
Effect.__index = Effect

---@param class table
---@return table
function Effect.extend(class)
    class.__index = class
    return setmetatable(class, Effect)
end

---@param self table
---@param bursts table[] # drawn in order
---@param life? number # s it lasts even once the bursts are empty
---@return table
function Effect.init(self, bursts, life)
    self.bursts, self.life, self.t = bursts, life or 0, 0
    return self
end

---@return boolean
function Effect:done()
    if self.t < self.life then return false end
    for _, burst in ipairs(self.bursts) do
        if #burst.particles > 0 then return false end
    end
    return true
end

---@param dt number
function Effect:update(dt)
    self.t = self.t + dt
    for _, burst in ipairs(self.bursts) do burst:update(dt) end
end

--- over the bursts, in design px; override
function Effect:drawOver() end

--- inside the camera
function Effect:draw()
    love.graphics.push("all")
    love.graphics.scale(Tile.worldScale())
    for _, burst in ipairs(self.bursts) do burst:draw() end
    self:drawOver()
    love.graphics.pop()
end

return Effect
