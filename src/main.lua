local Debug = require "core.debug"
local StateManager = require "core.stateManager"
local Presence = require "services.presence"
local Settings = require "core.settings"
local I18n = require "core.i18n"
local UI = require "ui"

-- Concrete game screens (live under src/, loaded via LÖVE's filesystem).
local loadingState = require "states.loading"
local mainMenuState = require "states.mainMenu"
local optionsState = require "states.options"
local Globals = require "globals"

local Stats = require "services.stats"

function love.load()
    love.window.setTitle(Globals.game.name)

    -- Size the UI to this window before anything asks the theme for a font or a
    -- metric — the loading screen warms the font cache on its very first task.
    UI.Theme.rescale()

    Globals.init()

    -- Load translations and select the saved language and palette before any
    -- screen draws, so even the loading screen is localized and wearing the
    -- theme the player left the game in.
    local settings = Settings.load()
    -- Read the opt-out before starting: the heartbeat must never fire for a
    -- player who turned it off, not even once at boot.
    Stats.enabled = settings.shareStats
    Stats.start()
    I18n.load()
    I18n.setLanguage(settings.language)
    UI.Theme.setTheme(settings.theme)

    -- Register every screen, then boot into the loading sequence.
    StateManager.register("loading", loadingState)
    StateManager.register("mainMenu", mainMenuState)
    StateManager.register("options", optionsState)

    StateManager.switch("loading")

    Presence.initialize()
end

function love.update(dt)
    StateManager.update(dt)
    Debug:update()
    Presence.update(dt)
    Stats.update(dt)
end

function love.quit()
    Presence.shutdown()
    Stats.shutdown()
end

function love.draw()
    StateManager.draw()
    Debug:draw()
    UI.Cursor.commit()
end

function love.resize(w, h)
    local rescaled = UI.Theme.rescale(h)
    StateManager.resize(w, h, rescaled)
end

function love.keypressed(key, scancode, isrepeat)
    if key == "f3" then
        Debug.toggle()
        return
    end
    StateManager.keypressed(key, scancode, isrepeat)
end

love.keyreleased   = StateManager.keyreleased
love.textinput     = StateManager.textinput
love.mousepressed  = StateManager.mousepressed
love.mousereleased = StateManager.mousereleased
love.mousemoved    = StateManager.mousemoved
love.wheelmoved    = StateManager.wheelmoved
