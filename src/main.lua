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

function love.load()
    love.window.setTitle("TD Idle")

    -- Size the UI to this window before anything asks the theme for a font or a
    -- metric — the loading screen warms the font cache on its very first task.
    UI.Theme.rescale()

    -- LÖVE seeds its own love.math RNG but not the stdlib math.random, so
    -- without this every "random" layout (stars, constellations, shooting
    -- stars) would be identical on every launch.
    math.randomseed(os.time())

    -- Load translations and select the saved language before any screen draws,
    -- so even the loading screen's own text is localized.
    I18n.load()
    I18n.setLanguage(Settings.load().language)

    -- Register every screen, then boot into the loading sequence.
    StateManager.register("loading", loadingState)
    StateManager.register("mainMenu", mainMenuState)
    StateManager.register("options", optionsState)
    StateManager.register("game", gameState)

    StateManager.switch("loading")

    Presence.initialize()
end

function love.update(dt)
    StateManager.update(dt)
    Debug:update()
    -- After StateManager, so a presence set during a state change is delivered
    -- in the same frame rather than the next one.
    Presence.update(dt)
end

-- Closes the Discord IPC connection on the way out so the presence clears
-- immediately instead of waiting for Discord to notice the process died.
-- Must not return a truthy value: that would abort the quit.
function love.quit()
    Presence.shutdown()
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
