--- The ground: an unbounded grid of TILE-sized squares. The world is meant to
-- be open, so there is no edge to walk into and nothing on the grid but
-- ground -- tile coordinates are 0-based and run negative in both directions.
-- World coordinates are tile pixels; the camera's zoom is what turns them into
-- screen space.
--
-- Ground has no art yet, so it draws as two alternating flat shades with the
-- grid picked out. Hand it a texture and every tile picks it up instead, and
-- the placeholder checker and gridlines go away with it:
--
--   world:setTexture(love.graphics.newImage("assets/tiles/grass.png"))

local Palette = require "game.palette"

local World = {}
World.__index = World

World.TILE = 32

local GRID_ALPHA = 0.55

---@param config? table # { texture?: love.Image }
---@return table
function World.new(config)
    config = config or {}
    local self = setmetatable({}, World)
    self:setTexture(config.texture)
    return self
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

--- the placeholder ground: an alternating checker with the grid picked out
---@param c1 integer # inclusive tile bounds
---@param r1 integer
---@param c2 integer
---@param r2 integer
function World:drawFlat(c1, r1, c2, r2)
    local tile = World.TILE
    local left, top = self:tileOrigin(c1, r1)
    local width = (c2 - c1 + 1) * tile
    local height = (r2 - r1 + 1) * tile

    love.graphics.setColor(Palette.ground)
    love.graphics.rectangle("fill", left, top, width, height)

    love.graphics.setColor(Palette.groundAlt)
    for row = r1, r2 do
        for col = c1, c2 do
            if (col + row) % 2 == 0 then
                love.graphics.rectangle("fill", col * tile, row * tile, tile, tile)
            end
        end
    end

    love.graphics.setColor(Palette.groundLine[1], Palette.groundLine[2],
        Palette.groundLine[3], GRID_ALPHA)
    for col = c1, c2 + 1 do
        love.graphics.line(col * tile, top, col * tile, top + height)
    end
    for row = r1, r2 + 1 do
        love.graphics.line(left, row * tile, left + width, row * tile)
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
