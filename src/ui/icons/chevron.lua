--- A small filled triangle pointing left or right, centred in a box -- the
-- arrows either side of a Selector's value. Draws in the current colour.

local Theme = require("ui.core.theme")

local Chevron = {}

local HALF_HEIGHT = 8 -- design px
local BACK = 5        -- flat edge, from the centre
local TIP = 6         -- point, from the centre

---@param x number # box
---@param y number
---@param w number
---@param h number
---@param dir -1|1 # left or right
function Chevron.draw(x, y, w, h, dir)
    local cx, cy = x + w / 2, y + h / 2
    local half, back, tip = Theme.px(HALF_HEIGHT), Theme.px(BACK) * dir, Theme.px(TIP) * dir
    love.graphics.polygon("fill", cx - back, cy - half, cx - back, cy + half, cx + tip, cy)
end

return Chevron
