--- Placeholder ground: grass tiles with scattered flowers (flat grid if the
-- art fails), the world's border.

local Math = require("utils.math")
local Noise = require("utils.noise")
local Textures = require("game.textures")
local Tile = require("game.tile")
local UI = require("ui")

local Ground = {}

-- not theme roles: grass ignores the UI theme
local GRASS = { 0.29, 0.50, 0.25 }
local GRID = { 0.24, 0.43, 0.21 }
local BORDER = 2
local GRASS_TEXTURE = "assets/textures/game/blocks/grass3.png"
local FLOWER_SHEET = "assets/textures/game/blocks/flower_sheet.png" -- square frames, side by side
local FLOWER_SEED = 7331
local PATCH_SIZE = 4      -- tiles across a typical flower patch
local PATCH_THRESHOLD = 0.75 -- patch noise above this grows flowers
local PATCH_DENSITY = 1.8    -- flowers per cell at a patch's heart
local STRAY_CHANCE = 0.005   -- of a lone flower outside patches
local PATCH_LOYALTY = 0.95    -- of a flower matching its patch's kind
local MAX_PER_CELL = 2

local flowerQuads = {}

--- one quad per square frame of the sheet
---@param sheet any # a love.Image
---@return table
local function quadsFor(sheet)
    if not flowerQuads[sheet] then
        local w, h = sheet:getDimensions()
        local quads = {}
        for i = 0, math.floor(w / h) - 1 do
            quads[#quads + 1] = love.graphics.newQuad(i * h, 0, h, h, w, h)
        end
        flowerQuads[sheet] = quads
    end
    return flowerQuads[sheet]
end

--- one image per cell; cells are whole screen px, so no seams
---@param image any # a love.Image
local function drawTiles(image, s, x0, y0, x1, y1)
    local step = Tile.SIZE * s
    local scale = step / image:getWidth()
    for cy = math.floor(y0 / Tile.SIZE), math.ceil(y1 / Tile.SIZE) - 1 do
        for cx = math.floor(x0 / Tile.SIZE), math.ceil(x1 / Tile.SIZE) - 1 do
            love.graphics.draw(image, Math.round(cx * step), Math.round(cy * step), 0, scale)
        end
    end
end

--- flowers per cell: patches from low-frequency noise, plus rare strays.
-- Fractional parts become a chance of one more.
local function flowerCount(cx, cy)
    local patch = Noise.fbm(cx / PATCH_SIZE, cy / PATCH_SIZE, FLOWER_SEED, 2)
    local density = STRAY_CHANCE
    if patch > PATCH_THRESHOLD then
        density = density + PATCH_DENSITY * (patch - PATCH_THRESHOLD) / (1 - PATCH_THRESHOLD)
    end
    local count = math.floor(density)
    if Noise.hash(cx, cy, FLOWER_SEED) < density - count then count = count + 1 end
    return math.min(count, MAX_PER_CELL)
end

--- flowers on some cells, picked by hashing the cell: the same every frame.
-- A patch mostly grows one kind. Drawn after all tiles so a neighbour never
-- covers one; offsets are whole texels so flower pixels line up with grass.
---@param sheet any # a love.Image
local function drawFlowers(sheet, s, x0, y0, x1, y1)
    local quads = quadsFor(sheet)
    local size = sheet:getHeight()
    local step = Tile.SIZE * s
    local texel = step / Tile.ART
    local span = Tile.ART - size + 1 -- offsets that keep it inside the cell
    local hash = Noise.hash
    for cy = math.floor(y0 / Tile.SIZE), math.ceil(y1 / Tile.SIZE) - 1 do
        for cx = math.floor(x0 / Tile.SIZE), math.ceil(x1 / Tile.SIZE) - 1 do
            local count = flowerCount(cx, cy)
            if count > 0 then
                local kind = Noise.value(cx / PATCH_SIZE, cy / PATCH_SIZE, FLOWER_SEED + 1)
                for i = 1, count do
                    local seed = FLOWER_SEED + i * 10
                    local pick = hash(cx, cy, seed) < PATCH_LOYALTY and kind or hash(cx, cy, seed + 1)
                    local quad = quads[math.min(#quads, math.floor(pick * #quads) + 1)]
                    -- a second flower takes the other half, so they don't overlap
                    local ox = math.floor(hash(cx, cy, seed + 2) * span)
                    local oy = math.floor(hash(cx, cy, seed + 3) * span)
                    if count > 1 then
                        local half = math.floor(span / 2)
                        oy = (i - 1) * half + oy % half
                    end
                    love.graphics.draw(sheet, quad,
                        Math.round(cx * step + ox * texel), Math.round(cy * step + oy * texel), 0, texel)
                end
            end
        end
    end
end

--- only the visible part; inside the camera
---@param world table
---@param camera table
function Ground.draw(world, camera)
    local Theme = UI.Theme
    local s = Tile.worldScale()
    local vx, vy, vw, vh = camera:view()
    local x0, x1 = math.max(0, vx), math.min(world.w, vx + vw)
    local y0, y1 = math.max(0, vy), math.min(world.h, vy + vh)
    local line = math.max(1, Theme.px(1))
    local left, top = Math.round(x0 * s), Math.round(y0 * s)
    local width, height = Math.round((x1 - x0) * s), Math.round((y1 - y0) * s)

    local image = Textures.get(GRASS_TEXTURE)
    if image then
        love.graphics.setColor(1, 1, 1, 1)
        drawTiles(image, s, x0, y0, x1, y1)
        local flowers = Textures.get(FLOWER_SHEET)
        if flowers then drawFlowers(flowers, s, x0, y0, x1, y1) end
    else
        Theme.setColor(GRASS)
        love.graphics.rectangle("fill", left, top, width, height)

        Theme.setColor(GRID)
        for gx = math.ceil(x0 / Tile.SIZE) * Tile.SIZE, x1, Tile.SIZE do
            love.graphics.rectangle("fill", Math.round(gx * s), top, line, height)
        end
        for gy = math.ceil(y0 / Tile.SIZE) * Tile.SIZE, y1, Tile.SIZE do
            love.graphics.rectangle("fill", left, Math.round(gy * s), width, line)
        end
    end

    Theme.setColor(Theme.colors.panelBorder)
    love.graphics.setLineWidth(math.max(1, Theme.px(BORDER)))
    love.graphics.rectangle("line", 0, 0, Math.round(world.w * s), Math.round(world.h * s))
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

return Ground
