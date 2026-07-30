-- src/gameTitle.lua
-- The game's chroma wordmark, shared by the loading screen and the main menu.
--
-- It lives here rather than privately inside mainMenu.lua so both screens draw
-- the *same* title at the *same* pose: the loading screen eases its copy into
-- the menu's position and size on the way out, so the state switch lands on an
-- identical frame instead of popping the title into existence.

local TextFactory = require "lib.textFactory"
local UI = require "lib.ui"
local Globals = require "globals"

local GameTitle = {}

GameTitle.TEXT = Globals.game.name

-- Vertical position on the main menu, as a fraction of the window height.
-- The loading screen's outro targets exactly this.
GameTitle.MENU_Y_RATIO = 0.16

-- Rebuild on resize: the wrap width is baked in at construction, and it's what
-- keeps the text horizontally centered.
function GameTitle.build()
    return TextFactory:new{
        text = GameTitle.TEXT,
        y = love.graphics.getHeight() * GameTitle.MENU_Y_RATIO,
        align = "center",
        font = UI.Theme.font("title"),
        gradient = { UI.Theme.colors.accent, UI.Theme.colors.accentAlt },
    }
end

-- Draws `title` with its top at `y`, scaled about the window's horizontal
-- center so it grows in place.
--
-- A transform rather than TextFactory:setSize because setSize allocates a new
-- Font and re-rasterizes the glyph mesh — fine once, ruinous every frame of an
-- animation. The chroma shader keys its hue off screen coordinates, so the
-- gradient's period scales along with the text; at these scales that reads as
-- part of the effect.
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
