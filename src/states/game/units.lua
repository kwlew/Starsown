-- src/states/game/units.lua
-- Everything in the game world is measured in meters: 1 m is one tile, and
-- positions, sizes, ranges, speeds (m/s) and gravity (m/s^2) all use it. The
-- one place meters meet screen pixels is the camera scale in Engine:draw.

local Units = {}

Units.PPM = 32 -- pixels per meter, at zoom 1

--- a size authored in pixels (line widths, bar heights, glow spreads, sprite
-- sizes), as meters - so it still looks the same once the camera scales it up
---@param pixels number
---@return number meters
function Units.px(pixels)
    return pixels / Units.PPM
end

--- what setLineWidth(1) means inside the camera transform
Units.LINE = Units.px(1)

return Units
