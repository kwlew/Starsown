--- One name, whichever art exists for it: the hand-drawn texture if there is
-- one, otherwise the procedural Glyph. Draws in the current colour.
--
--   Theme.setColor(Theme.colors.accent)
--   Icon.draw("gear", x, y, 32)

local Glyph = require("ui.icons.glyph")
local IconTexture = require("ui.icons.iconTexture")

local Icon = {}

---@param name string
---@param x number
---@param y number
---@param size number # screen pixels, a size x size box
function Icon.draw(name, x, y, size)
    local texture = IconTexture.get(name)
    if texture then
        IconTexture.draw(texture, x, y, size)
    else
        Glyph.draw(name, x, y, size)
    end
end

return Icon
