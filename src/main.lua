local Debug = require "lib.debug"
local StateManager = require "lib.stateManager"
local RPC = require "lib.discordRPC"
local Settings = require "lib.settings"
local I18n = require "lib.i18n"

-- Concrete game screens (live under src/, loaded via LÖVE's filesystem).
local loadingState = require "states.loading"
local mainMenuState = require "states.mainMenu"
local optionsState = require "states.options"

function love.run()
    if love.load then love.load(love.arg.parseGameArguments(arg), arg) end

    love.timer.step()

    local dt = 0

    return function()
        if love.event then
            love.event.pump()
            for name, a,b,c,d,e,f in love.event.poll() do
                if name == "quit" then
                    if not love.quit or not love.quit() then
                        return a or 0
                    end
                end
                love.handlers[name](a,b,c,d,e,f)
            end
        end

        dt = love.timer.step()

        if love.update then love.update(dt) end

        if love.graphics and love.graphics.isActive() then
            love.graphics.origin()
            love.graphics.clear(love.graphics.getBackgroundColor())
            if love.draw then love.draw() end
            love.graphics.present()
        end

        -- Only sleep if vsync is off AND you want a manual cap.
        -- Comment this out entirely for a true uncapped loop.
        love.timer.sleep(0.001)
    end
end

function love.load()
    love.window.setTitle("Game")

    -- Load translations and select the saved language before any screen draws,
    -- so even the loading screen's own text is localized.
    I18n.load()
    I18n.setLanguage(Settings.load().language)

    -- Register every screen, then boot into the loading sequence.
    StateManager.register("loading", loadingState)
    StateManager.register("mainMenu", mainMenuState)
    StateManager.register("options", optionsState)

    StateManager.switch("loading")

    RPC.initialize("1528201797863473362")
end

function love.update(dt)
    StateManager.update(dt)
    Debug:update()
    RPC.update()
end

function love.draw()
    StateManager.draw()
    Debug:draw()
end

-- Route input to whichever state is active.
love.keypressed    = StateManager.keypressed
love.keyreleased   = StateManager.keyreleased
love.textinput     = StateManager.textinput
love.mousepressed  = StateManager.mousepressed
love.mousereleased = StateManager.mousereleased
love.mousemoved    = StateManager.mousemoved
love.wheelmoved    = StateManager.wheelmoved
love.resize        = StateManager.resize
