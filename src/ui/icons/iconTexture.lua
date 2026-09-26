--- Hand-drawn button icons: `assets/textures/mainMenu/<name>_icon.png`, loaded
-- on first use and cached. Authored pure white so the caller's colour tints
-- them like a Glyph. A missing file isn't an error -- Button falls back to
-- the Glyph of the same name.

local IconTexture = {}

local DIR = "assets/textures/mainMenu/"

local cache = {}

---@param name string
---@return any # a love.Image, or nil when there's no texture for this name
function IconTexture.get(name)
    local cached = cache[name]
    if cached == nil then
        local path = DIR .. name .. "_icon.png"
        local ok, image = false, nil
        if love.filesystem.getInfo(path, "file") then
            ok, image = pcall(love.graphics.newImage, path)
            if not ok then print("[ui] failed to load " .. path .. ": " .. tostring(image)) end
        end
        cached = ok and image or false
        if cached then cached:setFilter("nearest", "nearest") end
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
    local scale = math.max(1, math.floor(size / math.max(w, h) + 0.5))
    love.graphics.draw(image,
        math.floor(x + (size - w * scale) / 2 + 0.5),
        math.floor(y + (size - h * scale) / 2 + 0.5),
        0, scale, scale)
end

return IconTexture
