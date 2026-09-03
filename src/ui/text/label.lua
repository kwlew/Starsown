local Theme = require "ui.core.theme"
local Text = require "ui.text.text"

local Label = {}

local SHADOW_OFFSET = 2

local HINT_BOTTOM = 48

--- the draw-time wrapper screens call instead of love.graphics.print, so
-- shadow offset and colour defaults live in one place
---@param opts table # { text?: string, x?: number, y?: number, width?: number, align?: string, font?: love.Font, color?: number[], alpha?: number, shadow?: boolean }
function Label.draw(opts)
    local font = opts.font or Theme.font("body")
    local width = opts.width or love.graphics.getWidth()
    local mesh = Text.get(opts.text or "", font, width, opts.align or "center")
    local x, y = opts.x or 0, opts.y or 0
    local color = opts.color or Theme.colors.text
    local alpha = opts.alpha or color[4] or 1

    if opts.shadow then
        local offset = Theme.px(SHADOW_OFFSET)
        local shadow = Theme.colors.shadow
        Theme.setColor(shadow, alpha * (shadow[4] or 1))
        love.graphics.draw(mesh, x + offset, y + offset)
    end

    Theme.setColor(color, alpha)
    love.graphics.draw(mesh, x, y)
    love.graphics.setColor(1, 1, 1, 1)
end

---@return integer # screen pixels, for callers laying out around a shadowed label
function Label.shadowOffset()
    return Theme.px(SHADOW_OFFSET)
end

---@return number # the y every screen's hint row sits at
function Label.hintY()
    return love.graphics.getHeight() - Theme.px(HINT_BOTTOM)
end

--- the dim one-line hint across the bottom of a screen
---@param text string
---@param shadow? boolean
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
