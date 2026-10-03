--- The dim one-line hint across the bottom of a screen ("Esc to go back").

local Theme = require("ui.core.theme")
local Label = require("ui.text.label")

local Hint = {}

local BOTTOM = 48 -- design px from the window's bottom edge

---@return number # the y every screen's hint row sits at
function Hint.y()
    return love.graphics.getHeight() - Theme.px(BOTTOM)
end

---@param text string
---@param shadow? boolean
function Hint.draw(text, shadow)
    Label.draw{
        text = text,
        y = Hint.y(),
        font = Theme.font("small"),
        color = Theme.colors.textMuted,
        shadow = shadow,
    }
end

return Hint
