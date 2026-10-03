--- Draws a swipe: a fading fan of spokes, the sword.

local Math = require("utils.math")
local Textures = require("game.textures")
local Tile = require("game.tile")
local UI = require("ui")

local Render = {}

local SWORD = "assets/textures/game/Stone_sword.png"
local SWORD_ANGLE = -math.pi / 4 -- the art points up-right
local GRIP_X, GRIP_Y = 2.5, 13.5 -- texels, from the art
local SPOKES = 32
local BLUR_ALPHA = 0.45

---@param swipe table
---@param angle number
---@param width number
---@param alpha number
local function spoke(swipe, angle, width, alpha)
    local ix, iy = Math.polar(swipe.x, swipe.y, angle, swipe.INNER)
    local tx, ty = Math.polar(swipe.x, swipe.y, angle, swipe.REACH)
    love.graphics.setLineWidth(width)
    UI.Theme.setColor(UI.Theme.colors.highlight, alpha)
    love.graphics.line(ix, iy, tx, ty)
end

--- the motion blur, fading back from the leading edge
---@param swipe table
---@param fade number
function Render.blur(swipe, fade)
    local tail, blade = -swipe.ARC / 2, swipe:bladeOffset()
    love.graphics.setBlendMode("add")
    for i = 0, SPOKES do
        local k = i / SPOKES
        spoke(swipe, swipe.angle + swipe.dir * (tail + (blade - tail) * k), 1 + 2 * k, fade * k * k * BLUR_ALPHA)
    end
    love.graphics.setBlendMode("alpha")
end

--- the sword on the leading edge, or a bright spoke
---@param swipe table
---@param fade number
function Render.sword(swipe, fade)
    local angle = swipe:bladeAngle()
    local image = Textures.get(SWORD)
    if not image then return spoke(swipe, angle, 4, fade * 0.9) end
    local gx, gy = Math.polar(swipe.x, swipe.y, angle, swipe.INNER)
    local texel = Tile.SIZE / Tile.ART
    love.graphics.setColor(1, 1, 1, fade)
    love.graphics.draw(image, gx, gy, angle - SWORD_ANGLE, texel, texel, GRIP_X, GRIP_Y)
end

--- inside the camera; design px scaled to the world
---@param swipe table
function Render.draw(swipe)
    love.graphics.push("all")
    love.graphics.scale(Tile.worldScale())
    if swipe.active then
        local fade = swipe:fade()
        Render.blur(swipe, fade)
        Render.sword(swipe, fade)
    end
    swipe.sparks:draw()
    swipe.impact:draw()
    love.graphics.pop()
end

return Render
