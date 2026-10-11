--- Small white textures shared by every particle effect; tint with setColor.

local Math = require("utils.math")

local Shapes = {}

Shapes.SIZE = 32

local cache = {}

---@param name string
---@param alpha fun(d: number): number # d is 0 centre .. 1 edge, in texture radii
---@return any # a love.Image
local function radial(name, alpha)
    if cache[name] then return cache[name] end
    local size = Shapes.SIZE
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
function Shapes.glow()
    return radial("glow", function(d)
        if d >= 1 then return 0 end
        return (1 - d * d) ^ 2
    end)
end

--- crisp disc with an antialiased rim
function Shapes.dot()
    local rim = 1 / ((Shapes.SIZE - 1) / 2)
    return radial("dot", function(d) return Math.clamp01((1 + rim - d) / rim) end)
end

--- pixel art from rows of text: "#" opaque, anything else clear
---@param name string
---@param rows string[]
---@return any # a love.Image
local function pixel(name, rows)
    if cache[name] then return cache[name] end
    local data = love.image.newImageData(#rows[1], #rows)
    data:mapPixel(function(x, y)
        return 1, 1, 1, rows[y + 1]:sub(x + 1, x + 1) == "#" and 1 or 0
    end)
    local image = love.graphics.newImage(data)
    image:setFilter("nearest", "nearest")
    cache[name] = image
    return image
end

--- one solid texel: chunks and debris
function Shapes.square()
    return pixel("square", { "#" })
end

--- a round pixel puff: smoke and dust
function Shapes.puff()
    return pixel("puff", {
        "..####..",
        ".######.",
        "########",
        "########",
        "########",
        "########",
        ".######.",
        "..####..",
    })
end

--- a 4-point hit flash
function Shapes.hitStar()
    return pixel("hitStar", {
        "...#...",
        "...#...",
        "..###..",
        "#######",
        "..###..",
        "...#...",
        "...#...",
    })
end

return Shapes
