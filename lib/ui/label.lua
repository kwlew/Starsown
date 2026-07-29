-- lib/ui/label.lua
-- Themed one-off text. Handles the setFont/setColor/restore dance so states
-- don't have to, and renders through UI.Text's mesh cache so a static heading
-- isn't laid out again on every frame.
--
--   Label.draw{ text = "OPTIONS", y = 100, font = Theme.font("heading") }
--   Label.draw{ text = "hint", y = 500, color = Theme.colors.textDim,
--               font = Theme.font("small"), alpha = 0.5 }

local Theme = require "lib.ui.theme"
local Text = require "lib.ui.text"

local Label = {}

-- Offset and opacity of the optional drop shadow. Small and soft: it exists to
-- keep text legible over the starfield, not to look like a shadow.
local SHADOW_OFFSET = 2
local SHADOW_ALPHA = 0.75

-- Distance from the bottom edge to the hint line, design-space px.
local HINT_BOTTOM = 48

-- `alpha` overrides the color's own, so a screen can fade a label without
-- building a tinted copy of a theme color every frame.
function Label.draw(opts)
    local font = opts.font or Theme.font("body")
    local width = opts.width or love.graphics.getWidth()
    local mesh = Text.get(opts.text or "", font, width, opts.align or "center")
    local x, y = opts.x or 0, opts.y or 0
    local color = opts.color or Theme.colors.text
    local alpha = opts.alpha or color[4] or 1

    -- Drawn from the same cached mesh, so the second pass is a draw call and
    -- nothing else. Use over busy backgrounds (the menu's hint sits directly on
    -- the stars, where dim text on a bright star all but disappears).
    if opts.shadow then
        local offset = Theme.px(SHADOW_OFFSET)
        love.graphics.setColor(0, 0, 0, alpha * SHADOW_ALPHA)
        love.graphics.draw(mesh, x + offset, y + offset)
    end

    Theme.setColor(color, alpha)
    love.graphics.draw(mesh, x, y)
    love.graphics.setColor(1, 1, 1, 1)
end

-- The dim one-line hint pinned above the bottom edge. `shadow` for a screen that
-- draws it straight onto the starfield.
function Label.hint(text, shadow)
    Label.draw{
        text = text,
        y = love.graphics.getHeight() - Theme.px(HINT_BOTTOM),
        font = Theme.font("small"),
        color = Theme.colors.textDim,
        shadow = shadow,
    }
end

return Label
