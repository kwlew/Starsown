--- The world's unit. Art is drawn at whole-number scales.

local Math = require("utils.math")
local UI = require("ui")

local Tile = {
    SIZE = 32, -- design px per tile
    ART = 16,  -- texels per tile
}

---@return integer # screen px per texel
function Tile.pixelScale()
    return math.max(1, Math.round(UI.Theme.scale * Tile.SIZE / Tile.ART))
end

--- screen px per world design px; use for anything in-world
---@return number
function Tile.worldScale()
    return Tile.pixelScale() * Tile.ART / Tile.SIZE
end

---@param tiles number
---@return number # design px
function Tile.px(tiles)
    return tiles * Tile.SIZE
end

return Tile
