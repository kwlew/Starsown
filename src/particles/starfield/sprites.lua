--- Batched halos and heads: two sprite batches, grown on demand.

local Textures = require("particles.textures")

local Sprites = {}

local TEXTURE = Textures.SIZE

local glows, heads
local glowCapacity, headCapacity = 0, 0

--- clears both batches, growing them to fit `stars`
---@param stars integer
function Sprites.begin(stars)
    if not glows or glowCapacity < stars then
        glowCapacity = math.max(stars, glowCapacity * 2, 16)
        glows = love.graphics.newSpriteBatch(Textures.glow(), glowCapacity, "stream")
    end
    if not heads or headCapacity < stars * 2 then
        headCapacity = math.max(stars * 2, headCapacity * 2, 32)
        heads = love.graphics.newSpriteBatch(Textures.dot(), headCapacity, "stream")
    end
    glows:clear()
    heads:clear()
end

---@param radius number # screen px
function Sprites.glow(x, y, radius, r, g, b, a)
    local scale = radius * 2 / TEXTURE
    glows:setColor(r, g, b, a)
    glows:add(x, y, 0, scale, scale, TEXTURE / 2, TEXTURE / 2)
end

---@param radius number # screen px
function Sprites.head(x, y, radius, r, g, b, a)
    local scale = radius * 2 / TEXTURE
    heads:setColor(r, g, b, a)
    heads:add(x, y, 0, scale, scale, TEXTURE / 2, TEXTURE / 2)
end

function Sprites.drawGlows()
    if glows:getCount() > 0 then love.graphics.draw(glows) end
end

function Sprites.drawHeads()
    if heads:getCount() > 0 then love.graphics.draw(heads) end
end

return Sprites
