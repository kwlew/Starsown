--- Batched halos and heads: two sprite batches, grown on demand.

local Math = require("utils.math")

local Sprites = {}

local GLOW_TEXTURE = 32
local HEAD_TEXTURE = 16

local glowImage, headImage
local glows, heads
local glowCapacity, headCapacity = 0, 0

---@param size integer
---@param alpha fun(dx: number, dy: number, center: number): number
---@return any # a love.Image
local function radialImage(size, alpha)
    local data = love.image.newImageData(size, size)
    local center = (size - 1) / 2
    data:mapPixel(function(x, y) return 1, 1, 1, alpha(x - center, y - center, center) end)
    local image = love.graphics.newImage(data)
    image:setFilter("linear", "linear")
    return image
end

local function softFalloff(dx, dy, center)
    local d2 = (dx * dx + dy * dy) / (center * center)
    if d2 >= 1 then return 0 end
    return (1 - d2) ^ 2
end

local function antialiasedDot(dx, dy, center)
    return Math.clamp01(center + 0.5 - math.sqrt(dx * dx + dy * dy))
end

--- clears both batches, growing them to fit `stars`
---@param stars integer
function Sprites.begin(stars)
    glowImage = glowImage or radialImage(GLOW_TEXTURE, softFalloff)
    headImage = headImage or radialImage(HEAD_TEXTURE, antialiasedDot)
    if not glows or glowCapacity < stars then
        glowCapacity = math.max(stars, glowCapacity * 2, 16)
        glows = love.graphics.newSpriteBatch(glowImage, glowCapacity, "stream")
    end
    if not heads or headCapacity < stars * 2 then
        headCapacity = math.max(stars * 2, headCapacity * 2, 32)
        heads = love.graphics.newSpriteBatch(headImage, headCapacity, "stream")
    end
    glows:clear()
    heads:clear()
end

---@param radius number # screen px
function Sprites.glow(x, y, radius, r, g, b, a)
    local scale = radius * 2 / GLOW_TEXTURE
    glows:setColor(r, g, b, a)
    glows:add(x, y, 0, scale, scale, GLOW_TEXTURE / 2, GLOW_TEXTURE / 2)
end

---@param radius number # screen px
function Sprites.head(x, y, radius, r, g, b, a)
    local scale = radius * 2 / HEAD_TEXTURE
    heads:setColor(r, g, b, a)
    heads:add(x, y, 0, scale, scale, HEAD_TEXTURE / 2, HEAD_TEXTURE / 2)
end

function Sprites.drawGlows()
    if glows:getCount() > 0 then love.graphics.draw(glows) end
end

function Sprites.drawHeads()
    if heads:getCount() > 0 then love.graphics.draw(heads) end
end

return Sprites
