--- A screen's last mouse position, and the cursor hover.

local UI = require("ui")

local Pointer = {}
Pointer.__index = Pointer

---@return table
function Pointer.new()
    local x, y = love.mouse.getPosition()
    return setmetatable({ x = x, y = y }, Pointer)
end

function Pointer:reset()
    self.x, self.y = love.mouse.getPosition()
end

---@param x number
---@param y number
function Pointer:move(x, y)
    self.x, self.y = x, y
end

--- lights the cursor over whatever `target` reports; call from update
---@param target table # answers hovering(x, y) -> hovering, danger
---@param extra? boolean # another reason to show hover
function Pointer:hover(target, extra)
    local over, danger = target:hovering(self.x, self.y)
    UI.Cursor.setHover(over or extra or false, danger)
end

return Pointer
