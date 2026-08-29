-- The game's chroma wordmark, shared by the loading screen and the main
-- menu. Lives here rather than privately inside mainMenu.lua so both screens
-- draw the *same* title at the *same* pose: the loading screen eases its
-- copy into the menu's position/size on the way out, landing the state
-- switch on an identical frame instead of popping the title into existence.

local TextFactory = require "ui.text.textFactory"
local UI = require "ui"
local Globals = require "globals"

local GameTitle = {}

GameTitle.TEXT = Globals.game.name

GameTitle.MENU_Y_RATIO = 0.16 -- vertical position on the menu, as a fraction of window height

-- the wordmark's two font choices, each its own Theme role (see
-- ui/core/theme.lua's fontRoles) so it can carry its own size/weight; picked
-- from Options (options.titleFont), "acme" is the original look
GameTitle.FONTS = {
    { id = "acme",     role = "title2" },
    { id = "orbitron", role = "title" },
}
GameTitle.current = "acme"

function GameTitle.available()
    return GameTitle.FONTS
end

-- unknown ids are ignored (GameTitle.current stays whatever it was), same
-- fall-back-to-current shape as an unrecognized saved setting elsewhere
function GameTitle.setFont(id)
    for _, entry in ipairs(GameTitle.FONTS) do
        if entry.id == id then
            GameTitle.current = id
            return true
        end
    end
    return false
end

local function currentFontRole()
    for _, entry in ipairs(GameTitle.FONTS) do
        if entry.id == GameTitle.current then return entry.role end
    end
    return "title2"
end

-- rebuild on resize: wrap width is baked in at construction. A theme change
-- needs no rebuild -- the gradient holds the theme's live color tables and
-- the shader reads them fresh every draw. A font or reduced-motion change
-- does need a rebuild (see GameTitle.setFont), which happens naturally next
-- time a screen calls this from its own enter()/resize().
function GameTitle.build()
    return TextFactory:new{
        text = GameTitle.TEXT,
        y = love.graphics.getHeight() * GameTitle.MENU_Y_RATIO,
        align = "center",
        font = UI.Theme.font(currentFontRole()),
        gradient = UI.Theme.titleGradient(),
        speed = UI.Motion.reduced and 0 or 1, -- reduced motion: color holds still instead of cycling
    }
end

-- draws `title` with its top at `y`, scaled about the window's horizontal
-- center. A transform rather than TextFactory:setSize, which reallocates a
-- Font and re-rasterizes the glyph mesh -- fine once, not every animation
-- frame. The chroma shader keys hue off screen coordinates, so the
-- gradient's period scales with the text, which reads as part of the effect.
function GameTitle.drawScaled(title, y, scale)
    local cx = love.graphics.getWidth() / 2
    title.y = y

    if scale == 1 then
        title:drawChroma()
        return
    end

    love.graphics.push()
    love.graphics.translate(cx, y)
    love.graphics.scale(scale, scale)
    love.graphics.translate(-cx, -y)
    title:drawChroma()
    love.graphics.pop()
end

return GameTitle
