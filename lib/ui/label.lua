-- lib/ui/label.lua
-- Themed one-off text. Handles the setFont/setColor/restore dance so states
-- don't have to.
--
--   Label.draw{ text = "OPTIONS", y = 100, font = Theme.font("heading") }
--   Label.draw{ text = "hint", y = 500, color = Theme.colors.textDim,
--               font = Theme.font("small") }

local Theme = require "lib.ui.theme"

local Label = {}

function Label.draw(opts)
    local font = opts.font or Theme.font("body")
    local previousFont = love.graphics.getFont()

    love.graphics.setFont(font)
    love.graphics.setColor(opts.color or Theme.colors.text)
    love.graphics.printf(
        opts.text or "",
        opts.x or 0,
        opts.y or 0,
        opts.width or love.graphics.getWidth(),
        opts.align or "center")

    love.graphics.setFont(previousFont)
    love.graphics.setColor(1, 1, 1, 1)
end

return Label
