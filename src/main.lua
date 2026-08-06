local Debug = require "lib.debug"
local StateManager = require "lib.stateManager"
local Presence = require "lib.presence"
local Settings = require "lib.settings"
local I18n = require "lib.i18n"
local UI = require "lib.ui"

-- Concrete game screens (live under src/, loaded via LÖVE's filesystem).
local loadingState = require "states.loading"
local mainMenuState = require "states.mainMenu"
local optionsState = require "states.options"
local gameState = require "states.game"
local achievementsState = require "states.achievements"
local pauseState = require "states.pause"
local Globals = require "globals"

local Stats = require "lib.stats"

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
    StateManager.register("game", gameState)
    StateManager.register("achievements", achievementsState)
    StateManager.register("pause", pauseState)

    StateManager.switch("loading")

    Presence.initialize()
end

function love.update(dt)
    StateManager.update(dt)
    Debug:update()
    -- After StateManager, so a presence set during a state change is delivered
    -- in the same frame rather than the next one.
    Presence.update(dt)
    Stats.update(dt)
end

-- Closes the Discord IPC connection and stops the stats heartbeat — which also
-- writes any popped stars that never made it out, so they go with the next one.
function love.quit()
    Presence.shutdown()
    Stats.shutdown()
end

function love.draw()
    StateManager.draw()
    Debug:draw()
    -- After every screen has had its say: the last UI.Cursor.want of the frame
    -- wins, and a frame where nobody asked resets to the arrow.
    UI.Cursor.commit()
end

-- The window only resizes when Options applies a new resolution or display
-- mode (conf.lua keeps it non-resizable), so this is where the UI scale is
-- recomputed. Fonts and metrics update globally; the active state is told to
-- relay out only when the scale actually moved.
function love.resize(w, h)
    local rescaled = UI.Theme.rescale(h)
    StateManager.resize(w, h, rescaled)
end

-- F3 is global: the dev overlay belongs to the game, not to any one screen, and
-- it must stay reachable even while a state is mid-transition.
function love.keypressed(key, scancode, isrepeat)
    if key == "f3" then
        Debug.toggle()
        return
    end
    StateManager.keypressed(key, scancode, isrepeat)
end

-- Route the rest of the input to whichever state is active.
love.keyreleased   = StateManager.keyreleased
love.textinput     = StateManager.textinput
love.mousepressed  = StateManager.mousepressed
love.mousereleased = StateManager.mousereleased
love.mousemoved    = StateManager.mousemoved
love.wheelmoved    = StateManager.wheelmoved
