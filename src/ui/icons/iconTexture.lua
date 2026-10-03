--- Hand-drawn button icons: `assets/textures/mainMenu/<name>_icon.png`, loaded
-- on first use and cached. Authored pure white so the current colour tints
-- them like a Glyph. A missing file isn't an error -- see Icon, which falls
-- back to the Glyph of the same name.

local Math = require("utils.math")

local IconTexture = {}

local DIR = "assets/textures/mainMenu/"

local cache = {} -- name -> love.Image, or false when there's no texture

---@param name string
---@return any # a love.Image, or nil when there's no texture for this name
function IconTexture.get(name)
    local cached = cache[name]
    if cached == nil then
        local path = DIR .. name .. "_icon.png"
        cached = false
        if love.filesystem.getInfo(path, "file") then
            local ok, image = pcall(love.graphics.newImage, path)
            if ok then
                image:setFilter("nearest", "nearest")
                cached = image
            else
                print("[ui] failed to load " .. path .. ": " .. tostring(image))
            end
        end
        cache[name] = cached
    end
    return cached or nil
end

--- draws in the current colour at the largest whole-number scale that best
-- fits `size`, so pixel art stays crisp; centred in the size x size box
---@param image any # a love.Image
---@param x number
---@param y number
---@param size number # screen pixels
function IconTexture.draw(image, x, y, size)
    local w, h = image:getDimensions()
    local scale = math.max(1, Math.round(size / math.max(w, h)))
    love.graphics.draw(image,
        Math.round(x + (size - w * scale) / 2),
        Math.round(y + (size - h * scale) / 2),
        0, scale, scale)
end

return IconTexture
