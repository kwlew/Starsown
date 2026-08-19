local Debug = require "core.debug"
local StateManager = require "core.stateManager"
local Presence = require "services.presence"
local Settings = require "core.settings"
local I18n = require "core.i18n"
local UI = require "ui"
local GameTitle = require "ui.text.gameTitle"

local loadingState = require "states.loading"
local mainMenuState = require "states.mainMenu"
local optionsState = require "states.options"
local Globals = require "globals"

local Stats = require "services.stats"

function love.load()
    love.window.setTitle(Globals.game.name)

    -- must run before anything else asks Theme for a font/metric
    UI.Theme.rescale()
    -- hides the OS cursor; UI.Cursor.draw() replaces it every frame
    UI.Cursor.init()

    Globals.init()

    -- load settings/language/theme before any screen draws, so the
    -- loading screen itself is already localized and themed
    local settings = Settings.load()
    Stats.enabled = settings.shareStats
    Stats.start()
    I18n.load()
    I18n.setLanguage(settings.language)
    UI.Theme.setTheme(settings.theme)
    GameTitle.setFont(settings.titleFont)
    UI.Cursor.setEnabled(settings.customCursor)

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
    UI.Cursor.update(dt)
    -- global so a crossfade still happens while sitting on Options
    UI.Music.update(dt)
end

function love.quit()
    Presence.shutdown()
    Stats.shutdown()
end

function love.draw()
    StateManager.draw()
    Debug:draw()
    UI.Cursor.draw()
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
