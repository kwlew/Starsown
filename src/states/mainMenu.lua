-- src/states/mainMenu.lua
-- Title screen: chroma title (via TextFactory) plus a keyboard/mouse menu of
-- themed buttons.

local StateManager = require "lib.stateManager"
local RPC = require "lib.discordRPC"
local Menu = require "lib.menu"
local TextFactory = require "lib.textFactory"
local UI = require "lib.ui"
local I18n = require "lib.i18n"
local Starfield = require "lib.starfield"

-- Layout is expressed as fractions of the window so it survives resizing and
-- runs at any resolution, instead of hardcoded pixel offsets.
local TITLE_Y_RATIO = 0.16
local MENU_Y_RATIO  = 0.44

-- Set once at load so the presence "elapsed" clock reflects the whole session
-- rather than restarting every time we return to the menu.
local SESSION_START = os.time()

local MENU_PRESENCE = {
    details = "Main Menu",
    state = "Getting ready",
    timestamps = { start = SESSION_START },
    assets = {
        large_image = "game_logo",
        large_text = "Game",
        small_image = "playing_icon",
        small_text = "In the menu",
    },
}

local MainMenu = {}

local function buildTitle()
    -- Rebuilt on enter/resize so its wrap width matches the current window
    -- and the text stays horizontally centered. Gradient runs through the
    -- theme's accent family so the title matches the rest of the UI.
    return TextFactory:new{
        text = "TD Idle",
        y = love.graphics.getHeight() * TITLE_Y_RATIO,
        align = "center",
        font = UI.Theme.font("title"),
        gradient = { UI.Theme.colors.accent, UI.Theme.colors.accentAlt },
    }
end

-- Pushes the menu presence once the RPC connection is actually ready. Called
-- repeatedly from update until it succeeds, because the connection comes up
-- asynchronously a moment after launch.
function MainMenu:pushPresence()
    if self.presenceSent then return end
    if RPC.isReady() and RPC.setActivity(MENU_PRESENCE) then
        self.presenceSent = true
    end
end

function MainMenu:enter()
    self.title = buildTitle()
    self.starfield = self.starfield or Starfield.new{}

    -- The menu itself is stateless between visits, so build it just once.
    -- Labels are functions so they re-read the active language every draw; a
    -- language change from Options updates the menu with no rebuild.
    self.menu = self.menu or Menu.new({
        { label = function() return I18n.t("menu.play") end, onSelect = function()
            -- No gameplay state yet. When it exists:
            -- StateManager.switch("game")
        end },
        { label = function() return I18n.t("menu.options") end, onSelect = function()
            StateManager.switch("options")
        end },
        { label = function() return I18n.t("menu.quit") end, onSelect = function()
            love.event.quit()
        end },
    })

    -- Re-assert menu presence every time we land here (e.g. back from options).
    self.presenceSent = false
    self:pushPresence()
end

function MainMenu:update(dt)
    self.starfield:update(dt)
    self.title:update(dt)
    self.menu:update(dt)
    self:pushPresence()
end

function MainMenu:resize()
    self.title = buildTitle()
end

function MainMenu:keypressed(key)
    self.menu:keypressed(key)
end

function MainMenu:mousemoved(x, y)
    self.menu:mousemoved(x, y)
end

function MainMenu:mousepressed(x, y, button)
    self.menu:mousepressed(x, y, button)
end

function MainMenu:mousereleased(x, y, button)
    self.menu:mousereleased(x, y, button)
end

function MainMenu:draw()
    local h = love.graphics.getHeight()

    self.starfield:draw()

    self.title.y = h * TITLE_Y_RATIO -- keep vertical position responsive
    self.title:drawChroma()

    self.menu:draw(h * MENU_Y_RATIO)

    UI.Label.draw{
        text = I18n.t("menu.hint"),
        y = h - 48,
        font = UI.Theme.font("small"),
        color = UI.Theme.colors.textDim,
    }
end

return MainMenu
