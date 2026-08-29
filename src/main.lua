local Debug = require "core.debug"
local StateManager = require "core.stateManager"
local Presence = require "services.presence"
local Settings = require "core.settings"
local FrameLimiter = require "core.frameLimiter"
local I18n = require "core.i18n"
local UI = require "ui"
local GameTitle = require "ui.text.gameTitle"

local loadingState = require "states.loading"
local Globals = require "globals"

local Stats = require "services.stats"

---@diagnostic disable-next-line: duplicate-set-field
function love.load()
    love.window.setTitle(Globals.game.name)

    UI.Theme.rescale()

    UI.Cursor.init()

    Globals.init()

    local settings = Settings.load()

    Stats.enabled = settings.statsConsentAsked and settings.shareStats
    Stats.start()
    I18n.load()
    I18n.setLanguage(settings.language)
    UI.Theme.setTheme(settings.theme)
    GameTitle.setFont(settings.titleFont)
    UI.Cursor.setEnabled(settings.customCursor)
    UI.Motion.setReduced(settings.reducedMotion)
    FrameLimiter.setUncapped(settings.uncapFps)

    StateManager.register("loading", loadingState)
    StateManager.switch("loading", settings)

    Presence.initialize()
end

function love.update(dt)
    StateManager.update(dt)
    Debug:update()
    Presence.update(dt)
    Stats.update(dt)
    UI.Cursor.update(dt)
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

---@diagnostic disable-next-line: duplicate-set-field
function love.run()
    ---@diagnostic disable-next-line: redundant-parameter
    if love.load then love.load(love.arg.parseGameArguments(arg), arg) end

    if love.timer then love.timer.step() end

    local dt = 0

    return function()
        if love.event then
            love.event.pump()
            for name, a, b, c, d, e, f in love.event.poll() do
                if name == "quit" then
                    if not love.quit or not love.quit() then
                        return a or 0
                    end
                end
                love.handlers[name](a, b, c, d, e, f)
            end
        end

        if love.timer then dt = love.timer.step() end

        if love.update then love.update(dt) end

        if love.graphics and love.graphics.isActive() then
            love.graphics.origin()
            love.graphics.clear(love.graphics.getBackgroundColor())
            if love.draw then love.draw() end
            love.graphics.present()
        end

        if love.timer and not FrameLimiter.uncapped then
            love.timer.sleep(0.001)
        end
    end
end
