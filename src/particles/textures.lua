--- Small white radial textures shared by every particle effect; tint with setColor.

local Math = require("utils.math")

local Textures = {}

Textures.SIZE = 32

local cache = {}

---@param name string
---@param alpha fun(d: number): number # d is 0 centre .. 1 edge, in texture radii
---@return any # a love.Image
local function radial(name, alpha)
    if cache[name] then return cache[name] end
    local size = Textures.SIZE
    local data = love.image.newImageData(size, size)
    local center = (size - 1) / 2
    data:mapPixel(function(x, y)
        local dx, dy = x - center, y - center
        return 1, 1, 1, alpha(math.sqrt(dx * dx + dy * dy) / center)
    end)
    local image = love.graphics.newImage(data)
    image:setFilter("linear", "linear")
    cache[name] = image
    return image
end

--- soft halo, brightest in the middle
function Textures.glow()
    return radial("glow", function(d)
        if d >= 1 then return 0 end
        return (1 - d * d) ^ 2
    end)
end

--- crisp disc with an antialiased rim
function Textures.dot()
    local rim = 1 / ((Textures.SIZE - 1) / 2)
    return radial("dot", function(d) return Math.clamp01((1 + rim - d) / rim) end)
end

return Textures
