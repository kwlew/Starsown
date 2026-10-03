--- Placeholder ground: grass, a tile grid, the world's border.

local Math = require("utils.math")
local Tile = require("game.tile")
local UI = require("ui")

local Ground = {}

-- not theme roles: grass ignores the UI theme
local GRASS = { 0.29, 0.50, 0.25 }
local GRID = { 0.24, 0.43, 0.21 }
local BORDER = 2

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

    Theme.setColor(GRASS)
    love.graphics.rectangle("fill", left, top, width, height)

    Theme.setColor(GRID)
    for gx = math.ceil(x0 / Tile.SIZE) * Tile.SIZE, x1, Tile.SIZE do
        love.graphics.rectangle("fill", Math.round(gx * s), top, line, height)
    end
    for gy = math.ceil(y0 / Tile.SIZE) * Tile.SIZE, y1, Tile.SIZE do
        love.graphics.rectangle("fill", left, Math.round(gy * s), width, line)
    end

    Theme.setColor(Theme.colors.panelBorder)
    love.graphics.setLineWidth(math.max(1, Theme.px(BORDER)))
    love.graphics.rectangle("line", 0, 0, Math.round(world.w * s), Math.round(world.h * s))
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

return Ground
