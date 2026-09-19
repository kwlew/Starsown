-- src/states/game/rendering/world.lua
-- Here will be handled world properties:
-- Tile size, Tiles, World size, World generation, etc.

local Palette = require "states.game.rendering.palette"

local World = {}
World.__index = World

World.TILE = 32 -- pixels

local GRID_ALPHA = 0.55

function World.new(config)
    config = config or {}
    local self = setmetatable({}, World)
    return self
end

function World:toTile(x, y)
    return math.floor(x / World.TILE), math.floor(y / World.TILE)
end

function World:tileOrigin(col, row)
    return col * World.TILE, row * World.TILE
end

--- The middle of a tile, where anything placed on the grid stands. Static, so
-- grid-placed things (trees and whatever follows) can snap without a world.
---@param col integer
---@param row integer
---@return number x
---@return number y
function World.tileCenter(col, row)
    local half = World.TILE / 2
    return col * World.TILE + half, row * World.TILE + half
end

function World:drawFlat(c1, r1, c2, r2)
    local tile = World.TILE
    local left, top = self:tileOrigin(c1, r1)
    local width = (c2 - c1 + 1 ) * tile
    local height = (r2 - r1 + 1) * tile

    love.graphics.setColor(Palette.tiles.Grass)
    love.graphics.rectangle("fill", left, top, width, height)

    love.graphics.setColor(Palette.tiles.Grass2)
    for row = r1, r2 do
        for col = c1, c2 do
            if (col + row) % 2 == 0 then
                love.graphics.rectangle("fill", col * tile, row * tile, tile, tile)
            end
        end
    end

    love.graphics.setColor(Palette.gridLine[1], Palette.gridLine[2], Palette.gridLine[3], GRID_ALPHA)

    for col = c1, c2 do
        love.graphics.line(col * tile, top, col * tile, top + height)
    end

    for row = r1, r2 do
        love.graphics.line(left, row * tile, left + width, row * tile)
    end
end

function World:update(dt) end

function World:draw(x1, y1, x2, y2)
    
    local c1, r1 = self:toTile(x1, y1)
    local c2, r2 = self:toTile(x2, y2)

    self:drawFlat(c1, r1, c2, r2)

end

return World