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

--- boot: scale the UI, read settings, apply language/theme/cursor/motion, then
-- hand off to the loading screen, which owns the rest of the load
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

--- the current state, then everything that runs regardless of which screen is
-- up: the debug sampler, Discord presence, the stats heartbeat, the cursor and
-- the menu music crossfade
---@param dt number
function love.update(dt)
    StateManager.update(dt)
    Debug:update()
    Presence.update(dt)
    Stats.update(dt)
    UI.Cursor.update(dt)
    UI.Music.update(dt)
end

--- closes the Discord connection and saves any undelivered stats backlog
function love.quit()
    Presence.shutdown()
    Stats.shutdown()
end

--- the current state, the F3 panel, then the cursor over everything
function love.draw()
    StateManager.draw()
    Debug:draw()
    UI.Cursor.draw()
end

--- rescales the UI first, then tells the state -- which is passed whether the
-- scale actually changed, since only then do cached fonts and labels need
-- rebuilding
---@param w number
---@param h number
function love.resize(w, h)
    local rescaled = UI.Theme.rescale(h)
    StateManager.resize(w, h, rescaled)
end

--- F3 chords are routed to the state's chordpressed instead of its keypressed;
-- see core/debug.lua
---@param key string
---@param scancode string
---@param isrepeat boolean
function love.keypressed(key, scancode, isrepeat)
    local consumed, chord = Debug.keypressed(key, isrepeat)
    if chord then
        StateManager.chordpressed(chord)
        return
    end
    if consumed then return end
    StateManager.keypressed(key, scancode, isrepeat)
end

---@param key string
---@param scancode string
function love.keyreleased(key, scancode)
    if Debug.keyreleased(key) then return end
    StateManager.keyreleased(key, scancode)
end

love.textinput     = StateManager.textinput
love.mousepressed  = StateManager.mousepressed
love.mousereleased = StateManager.mousereleased
love.mousemoved    = StateManager.mousemoved
love.wheelmoved    = StateManager.wheelmoved

--- LÖVE's main loop, replaced only to make the frame cap optional: the stock
-- loop always sleeps, and the uncapFps setting needs that to be conditional
---@return fun(): integer|nil # the per-frame step; returns an exit code to quit
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
