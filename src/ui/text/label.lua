-- Themed one-off text. Handles the setFont/setColor/restore dance so states
-- don't have to, and renders through UI.Text's mesh cache so a static
-- heading isn't laid out again every frame.
--
--   Label.draw{ text = "OPTIONS", y = 100, font = Theme.font("heading") }
--   Label.draw{ text = "hint", y = 500, color = Theme.colors.textDim,
--               font = Theme.font("small"), alpha = 0.5 }

local Theme = require "ui.core.theme"
local Text = require "ui.text.text"

local Label = {}

local SHADOW_OFFSET = 2 -- design-space px; small and soft, just enough to read over the starfield

local HINT_BOTTOM = 48 -- distance from the bottom edge to the hint line, design-space px

-- `alpha` overrides the color's own, so a screen can fade a label without building a tinted color copy
function Label.draw(opts)
    local font = opts.font or Theme.font("body")
    local width = opts.width or love.graphics.getWidth()
    local mesh = Text.get(opts.text or "", font, width, opts.align or "center")
    local x, y = opts.x or 0, opts.y or 0
    local color = opts.color or Theme.colors.text
    local alpha = opts.alpha or color[4] or 1

    -- same cached mesh, so the shadow pass is just another draw call; use
    -- over busy backgrounds (the menu hint sits directly on the stars)
    if opts.shadow then
        local offset = Theme.px(SHADOW_OFFSET)
        local shadow = Theme.colors.shadow
        Theme.setColor(shadow, alpha * (shadow[4] or 1)) -- multiplied, so a fading label takes its shadow with it
        love.graphics.draw(mesh, x + offset, y + offset)
    end

    Theme.setColor(color, alpha)
    love.graphics.draw(mesh, x, y)
    love.graphics.setColor(1, 1, 1, 1)
end

-- exposed so a screen whose own furniture can grow into this line can tell
-- (see Options, whose per-row description yields the hint on collision)
function Label.hintY()
    return love.graphics.getHeight() - Theme.px(HINT_BOTTOM)
end

function Label.hint(text, shadow)
    Label.draw{
        text = text,
        y = Label.hintY(),
        font = Theme.font("small"),
        color = Theme.colors.textDim,
        shadow = shadow,
    }
end

return Label
