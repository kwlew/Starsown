--- Small white textures shared by every particle effect; tint with setColor.
-- Soft ones are generated; pixel art lives in assets/textures/particles/.

local Math = require("utils.math")

local Shapes = {}

Shapes.SIZE = 32

local DIR = "assets/textures/particles/"
local BUILT_IN = { glow = true, dot = true, square = true }

local cache = {} -- generated, by name
local files = {} -- loaded, by name; false if missing

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

--- one solid texel
function Shapes.square()
    return pixel("square", { "#" })
end

--- a built-in shape by name, or a pixel-art file: a bare name is
-- assets/textures/particles/<name>.png, anything with a "/" a full path.
-- A missing file falls back to a square.
---@param name string
---@return any # a love.Image
function Shapes.get(name)
    if BUILT_IN[name] then return Shapes[name]() end
    if files[name] == nil then
        local path = name:find("/") and name or DIR .. name .. ".png"
        local ok, image = pcall(love.graphics.newImage, path)
        if ok then
            image:setFilter("nearest", "nearest")
        else
            print("[particles] failed to load " .. path .. ": " .. tostring(image))
        end
        files[name] = ok and image
    end
    return files[name] or Shapes.square()
end

return Shapes
