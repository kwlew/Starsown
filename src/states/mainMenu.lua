-- src/states/mainMenu.lua
-- Title screen: chroma title (via TextFactory) plus a keyboard menu.

local StateManager = require "lib.stateManager"
local Menu = require "lib.menu"
local Assets = require "lib.assets"
local TextFactory = require "lib.textFactory"

local MainMenu = {}

function MainMenu:enter()
    -- Built once, then reused every time we return to the menu.
    self.title = self.title or TextFactory:new{
        text = "TD Idle",
        y = 120,
        align = "center",
        size = 72,
        gradient = { { 1, 0, 0 }, { 0, 1, 1 } }, -- red -> blue chroma
    }

    self.menu = self.menu or Menu.new({
        { label = "Play", onSelect = function()
            -- No gameplay state yet. When it exists:
            -- StateManager.switch("game")
        end },
        { label = "Options", onSelect = function()
            StateManager.switch("options")
        end },
        { label = "Quit", onSelect = function()
            love.event.quit()
        end },
    }, Assets.get("menuFont"))
end

function MainMenu:update(dt)
    self.title:update(dt)
end

function MainMenu:keypressed(key)
    self.menu:keypressed(key)
end

function MainMenu:draw()
    self.title:drawChroma()
    self.menu:draw(340, 46)
end

return MainMenu
