-- The pause overlay: a scrim, a heading and a menu over whatever the screen
-- last drew. It owns nothing about the game -- the screen decides what pausing
-- means and passes in what the entries do.
--
--   self.pause = PauseMenu.new{
--       items = { { label = ..., onSelect = ... }, ... },
--       onCancel = function() self:resume() end,  -- Esc
--   }

local Theme = require "ui.core.theme"
local Menu = require "ui.widgets.menu"
local Label = require "ui.text.label"
local Sfx = require "ui.core.sfx"
local I18n = require "core.i18n"

local PauseMenu = {}
PauseMenu.__index = PauseMenu

local HEADING_Y_RATIO = 0.26
local MENU_Y_RATIO = 0.40

function PauseMenu.new(config)
    local self = setmetatable({
        open = false,
        onCancel = config.onCancel,
        menu = Menu.new(config.items),
    }, PauseMenu)

    self.menu:onFocusChanged(Sfx.focus)
    self:layout()
    return self
end

function PauseMenu:isOpen()
    return self.open
end

function PauseMenu:openMenu()
    self.open = true
    self.menu:setFocus(1) -- always lands on Resume, never on wherever it was left
    self:layout()
end

function PauseMenu:close()
    self.open = false
end

function PauseMenu:layout()
    self.menu:layout(love.graphics.getHeight() * MENU_Y_RATIO)
end

function PauseMenu:update(dt)
    self.menu:update(dt)
end

function PauseMenu:keypressed(key)
    if key == "escape" then
        if self.onCancel then self.onCancel() end
        return true
    end
    return self.menu:keypressed(key)
end

function PauseMenu:mousemoved(x, y)     return self.menu:mousemoved(x, y)        end
function PauseMenu:mousepressed(x, y, b) return self.menu:mousepressed(x, y, b)  end
function PauseMenu:mousereleased(x, y, b) return self.menu:mousereleased(x, y, b) end
function PauseMenu:hovering(x, y)       return self.menu:hovering(x, y)          end

function PauseMenu:draw()
    Theme.setColor(Theme.colors.scrim)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())

    Label.draw{
        text = I18n.t("game.pause.title"),
        y = love.graphics.getHeight() * HEADING_Y_RATIO,
        font = Theme.font("heading"),
        shadow = true,
    }

    self.menu:draw()
    love.graphics.setColor(1, 1, 1, 1)
end

return PauseMenu
