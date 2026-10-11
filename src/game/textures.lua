--- Pixel-art images by path, loaded once; missing is false.

local Textures = {}

local cache = {}

---@param path string
---@return any # a love.Image, or false
function Textures.get(path)
    if cache[path] == nil then
        local ok, image = pcall(love.graphics.newImage, path)
        if ok then
            image:setFilter("nearest", "nearest")
        else
            print("[game] failed to load " .. path .. ": " .. tostring(image))
        end
        cache[path] = ok and image
    end
    return cache[path]
end

local palettes = {}
local OUTLINE = 0.2 -- brightest channel at or below this is outline

--- the art's opaque pixel colours bar its dark outline, one entry per
-- pixel, so common colours come up more; empty if the art fails
---@param path string
---@return number[][]
function Textures.palette(path)
    if palettes[path] == nil then
        local colors = {}
        local ok, data = pcall(love.image.newImageData, path)
        if ok then
            data:mapPixel(function(x, y, r, g, b, a)
                if a > 0.5 and math.max(r, g, b) > OUTLINE then colors[#colors + 1] = { r, g, b } end
                return r, g, b, a
            end)
        end
        palettes[path] = colors
    end
    return palettes[path]
end

return Textures
