-- src/states/game/rendering/world.lua
-- Here will be handled world properties:
-- Tile size, Tiles, World size, World generation, etc.

local Palette = require "states.game.rendering.palette"
local Biomes = require "states.game.biomes"

local World = {}
World.__index = World

local GRID_ALPHA = 0.55

---@param config? { seed?: integer } # same seed, same world; random when omitted
function World.new(config)
    config = config or {}
    local self = setmetatable({}, World)
    self.seed = config.seed or love.math.random(1, 2147483646)
    self.biomes = Biomes.new(self.seed)
    return self
end

---@param col integer
---@param row integer
---@return string biome # a Biomes id
function World:biomeAt(col, row)
    return self.biomes.at(col, row)
end

--- A tile is one meter square, so its coordinates are the floor of the position.
---@return integer col
---@return integer row
function World:toTile(x, y)
    return math.floor(x), math.floor(y)
end

--- The middle of a tile, where anything placed on the grid stands. Static, so
-- grid-placed things (trees and whatever follows) can snap without a world.
---@param col integer
---@param row integer
---@return number x
---@return number y
function World.tileCenter(col, row)
    return col + 0.5, row + 0.5
end

function World:drawFlat(c1, r1, c2, r2)
    local left, top = c1, r1
    local width, height = c2 - c1 + 1, r2 - r1 + 1

    love.graphics.setColor(Palette.tiles.Grass)
    love.graphics.rectangle("fill", left, top, width, height)

    love.graphics.setColor(Palette.tiles.Grass2)
    for row = r1, r2 do
        for col = c1, c2 do
            if (col + row) % 2 == 0 then
                love.graphics.rectangle("fill", col, row, 1, 1)
            end
        end
    end

    love.graphics.setColor(Palette.gridLine[1], Palette.gridLine[2], Palette.gridLine[3], GRID_ALPHA)

    for col = c1, c2 do
        love.graphics.line(col, top, col, top + height)
    end

    for row = r1, r2 do
        love.graphics.line(left, row, left + width, row)
    end
end

function World:update(dt) end

function World:draw(x1, y1, x2, y2)
    
    local c1, r1 = self:toTile(x1, y1)
    local c2, r2 = self:toTile(x2, y2)

    self:drawFlat(c1, r1, c2, r2)

end

return World