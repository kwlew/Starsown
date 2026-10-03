--- The fixed design space the menu sky is authored in.

local Sky = {}

Sky.W, Sky.H = 1920, 1080

--- uniform scale that covers the window, cropping evenly
---@param w number
---@param h number
---@return number scale
---@return number x # top-left on screen
---@return number y
function Sky.cover(w, h)
    local scale = math.max(w / Sky.W, h / Sky.H)
    return scale, (w - Sky.W * scale) / 2, (h - Sky.H * scale) / 2
end

--- a screen point in sky coordinates
---@param x number
---@param y number
---@return number
---@return number
function Sky.toSky(x, y)
    local scale, ox, oy = Sky.cover(love.graphics.getDimensions())
    return (x - ox) / scale, (y - oy) / scale
end

return Sky
