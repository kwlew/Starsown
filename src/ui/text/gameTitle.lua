--- The game's chroma wordmark, shared by the loading screen and the main
-- menu, so both draw the *same* title at the *same* pose and the loading
-- screen can ease its copy into the menu's position without a pop.
--
--   local title = GameTitle.build()
--   GameTitle.drawScaled(title, y, 1)

local Globals = require("globals")
local Motion = require("ui.core.motion")
local TextFactory = require("ui.text.textFactory")
local Theme = require("ui.core.theme")

local GameTitle = {}

GameTitle.TEXT = Globals.game.name

GameTitle.MENU_Y_RATIO = 0.16 -- vertical position on the menu, as a fraction of window height

GameTitle.FONTS = {
    { id = "acme",     role = "title2" },
    { id = "orbitron", role = "title" },
    { id = "jetmono",  role = "title3" },
}
GameTitle.current = GameTitle.FONTS[1].id

local roleFor = {}
for _, entry in ipairs(GameTitle.FONTS) do roleFor[entry.id] = entry.role end

---@return table[] # { id: string, role: string }[]; the selectable title faces
function GameTitle.available()
    return GameTitle.FONTS
end

--- unknown ids are ignored, same fall-back-to-current shape as an
-- unrecognized saved setting elsewhere
---@param id string
---@return boolean # changed; false if no face goes by that id
function GameTitle.setFont(id)
    if not roleFor[id] then return false end
    GameTitle.current = id
    return true
end

---@return string # the theme font role for the selected face
function GameTitle.currentRole()
    return roleFor[GameTitle.current]
end

--- Rebuild on resize (the wrap width is baked in) and after a font or
-- reduced-motion change. A theme change needs no rebuild: the gradient holds
-- the theme's live colour tables, and the shader reads them every draw.
---@return table # a TextFactory at the menu's pose
function GameTitle.build()
    return TextFactory.new{
        text = GameTitle.TEXT,
        y = love.graphics.getHeight() * GameTitle.MENU_Y_RATIO,
        align = "center",
        font = Theme.font(GameTitle.currentRole()),
        gradient = Theme.titleGradient(),
        speed = Motion.reduced and 0 or 1, -- reduced motion: colour holds still instead of cycling
    }
end

--- draws `title` with its top at `y`, scaled about the window's horizontal
-- centre. A transform rather than TextFactory:setSize, which re-rasterizes
-- -- fine once, not every animation frame.
---@param title table # a TextFactory from build()
---@param y number # top of the text
---@param scale number # 1 draws untransformed
function GameTitle.drawScaled(title, y, scale)
    title.y = y
    if scale == 1 then
        title:drawChroma()
        return
    end

    local cx = love.graphics.getWidth() / 2
    love.graphics.push()
    love.graphics.translate(cx, y)
    love.graphics.scale(scale, scale)
    love.graphics.translate(-cx, -y)
    title:drawChroma()
    love.graphics.pop()
end

return GameTitle
