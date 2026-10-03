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

return Textures
