--- The ground: an unbounded grid of TILE-sized squares. The world is meant to
-- be open, so there is no edge to walk into and nothing on the grid but
-- ground -- tile coordinates are 0-based and run negative in both directions.
-- World coordinates are tile pixels; the camera's zoom is what turns them into
-- screen space.
--
-- There is exactly one World for the whole game (see states/play.lua) --
-- areas aren't separate instances any more, just named rings of distance
-- from the origin (see game/areas.lua). Ground has no art yet, so it draws
-- as two alternating flat shades with the grid picked out, and which
-- shades a given tile uses comes from Areas.at(tileX, tileY) -- the Hub's
-- slate plaza vs. the Wastes' default grass, resolved per tile so the
-- palette actually changes exactly at a ring boundary. Hand the whole
-- world a texture and every tile picks it up instead, uniformly, and the
-- placeholder checker and per-area palettes go away with it:
--
--   world:setTexture(love.graphics.newImage("assets/tiles/grass.png"))

local Palette = require "game.palette"
local Areas = require "game.areas"

local World = {}
World.__index = World

World.TILE = 32

local GRID_ALPHA = 0.55

---@return table
function World.new()
    return setmetatable({}, World)
end

---@param image any # a love.Image, or nil
function World:setTexture(image)
    self.texture = image
    if image then
        self.textureScaleX = World.TILE / image:getWidth()
        self.textureScaleY = World.TILE / image:getHeight()
    end
end

--- world point -> tile coordinates
---@param x number
---@param y number
---@return integer col
---@return integer row
function World:toTile(x, y)
    return math.floor(x / World.TILE), math.floor(y / World.TILE)
end

---@param col integer
---@param row integer
---@return number # x, the tile's top-left corner in world units
---@return number y
function World:tileOrigin(col, row)
    return col * World.TILE, row * World.TILE
end

---@param c1 integer # inclusive tile bounds
---@param r1 integer
---@param c2 integer
---@param r2 integer
function World:drawTextured(c1, r1, c2, r2)
    local tile, image = World.TILE, self.texture
    local scaleX, scaleY = self.textureScaleX, self.textureScaleY

    love.graphics.setColor(1, 1, 1, 1)
    for row = r1, r2 do
        for col = c1, c2 do
            love.graphics.draw(image, col * tile, row * tile, 0, scaleX, scaleY)
        end
    end
end

--- the placeholder ground: an alternating checker with the grid picked out,
-- one tile at a time -- which area (and so which palette) a tile belongs to
-- can change from one tile to the next near a ring boundary, so there's no
-- single fill-the-whole-rect-at-once shortcut any more. Each tile draws its
-- own border in its own area's line colour too, so two tiles sharing an
-- edge across a boundary very occasionally overdraw each other rather than
-- one winning arbitrarily -- a fine trade at flat-placeholder fidelity, and
-- moot once real tile art replaces this entirely.
---@param c1 integer # inclusive tile bounds
---@param r1 integer
---@param c2 integer
---@param r2 integer
function World:drawFlat(c1, r1, c2, r2)
    local tile = World.TILE

    for row = r1, r2 do
        for col = c1, c2 do
            local x, y = col * tile, row * tile
            local area = Areas.at(x + tile / 2, y + tile / 2) -- the tile's centre decides its area
            local ground = (area.ground and Palette[area.ground]) or Palette.ground
            local groundAlt = (area.groundAlt and Palette[area.groundAlt]) or Palette.groundAlt
            local groundLine = (area.groundLine and Palette[area.groundLine]) or Palette.groundLine

            love.graphics.setColor((col + row) % 2 == 0 and groundAlt or ground)
            love.graphics.rectangle("fill", x, y, tile, tile)

            love.graphics.setColor(groundLine[1], groundLine[2], groundLine[3], GRID_ALPHA)
            love.graphics.rectangle("line", x, y, tile, tile)
        end
    end
end

--- only the tiles inside the camera's view; there is no other bound on them
---@param x1 number # world rect, from Camera:view()
---@param y1 number
---@param x2 number
---@param y2 number
function World:draw(x1, y1, x2, y2)
    local c1, r1 = self:toTile(x1, y1)
    local c2, r2 = self:toTile(x2, y2)

    if self.texture then
        self:drawTextured(c1, r1, c2, r2)
    else
        self:drawFlat(c1, r1, c2, r2)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return World
