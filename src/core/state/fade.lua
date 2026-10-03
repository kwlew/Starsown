--- The fade-through-background between two states.

local Theme = require("ui.core.theme")

local Fade = {}
Fade.__index = Fade

local HALF = 0.14 -- seconds for each half

---@param name string # destination state
---@param args table # packed enter() arguments
---@return table
function Fade.new(name, args)
    return setmetatable({ phase = "out", t = 0, name = name, args = args }, Fade)
end

--- advances; returns true once, at the midpoint
---@param dt number
---@return boolean midpoint
---@return boolean finished
function Fade:update(dt)
    self.t = self.t + dt
    if self.t < HALF then return false, false end
    if self.phase == "out" then
        self.phase, self.t = "in", 0
        return true, false
    end
    return false, true
end

---@return number # 0..1 cover opacity
function Fade:alpha()
    local k = math.min(1, self.t / HALF)
    return self.phase == "out" and k or 1 - k
end

function Fade:draw()
    local alpha = self:alpha()
    if alpha <= 0 then return end
    Theme.setColor(Theme.colors.bg, alpha)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())
    love.graphics.setColor(1, 1, 1, 1)
end

return Fade
