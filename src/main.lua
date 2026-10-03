--- Wires LÖVE's callbacks to the game; no logic here.

local App = require("core.app")
local Apply = require("core.settings.apply")
local Args = require("core.args")
local Assets = require("core.assets")
local Chords = require("core.debug.chords")
local DebugOverlay = require("core.debug.overlay")
local I18n = require("core.i18n")
local Music = require("core.audio.music")
local Presence = require("services.presence")
local Settings = require("core.settings")
local Sounds = require("core.audio.sounds")
local StateManager = require("core.state.manager")
local Stats = require("services.stats")
local UI = require("ui")

--- `--check-https` verifies a build; `--stats-endpoint <url>` tests stats
---@param args string[]
---@diagnostic disable-next-line: duplicate-set-field
function love.load(args)
    if Args.has(args, "--check-https") then
        local ok, err = Stats.checkHttps()
        print(ok and "[check-https] ok" or ("[check-https] failed: " .. err))
        os.exit(ok and 0 or 1)
    end

    love.window.setTitle(App.NAME)
    App.init()
    UI.Theme.rescale()

    local settings = Settings.load()
    I18n.load()
    Apply.interface(settings)
    Apply.cursor(settings)
    UI.Sfx.setPlayer(Sounds.ui)

    local endpoint = Args.value(args, "--stats-endpoint")
    if endpoint then Stats.setEndpoint(endpoint) end
    Stats.enabled = settings.statsConsentAsked and settings.shareStats
    Stats.start()

    StateManager.register("loading", require("states.loading"))
    StateManager.switch("loading", settings)
    Presence.initialize()
end

---@param dt number
function love.update(dt)
    StateManager.update(dt) -- first: screens set the cursor's hover
    DebugOverlay.update()
    Presence.update(dt)
    Stats.update(dt)
    UI.Cursor.update(dt)
    Music.update(dt)
end

function love.draw()
    StateManager.draw()
    DebugOverlay.draw()
    UI.Cursor.draw()
end

---@param w number
---@param h number
function love.resize(w, h)
    local rescaled = UI.Theme.rescale(h)
    local settings = Assets.get("settings")
    if settings then Settings.trackWindowResize(settings, w, h) end
    StateManager.resize(w, h, rescaled)
end

function love.keypressed(key, scancode, isrepeat)
    local consumed, chord = Chords.keypressed(key, isrepeat)
    if chord then return StateManager.chordpressed(chord) end
    if not consumed then StateManager.keypressed(key, scancode, isrepeat) end
end

function love.keyreleased(key, scancode)
    if not Chords.keyreleased(key) then StateManager.keyreleased(key, scancode) end
end

function love.mousepressed(x, y, button, ...)
    UI.Cursor.mousepressed(x, y, button)
    StateManager.mousepressed(x, y, button, ...)
end

love.textinput = StateManager.textinput
love.mousereleased = StateManager.mousereleased
love.mousemoved = StateManager.mousemoved
love.wheelmoved = StateManager.wheelmoved
love.focus = StateManager.focus

--- worker errors are reported by their service, not fatal
---@diagnostic disable-next-line: duplicate-set-field
function love.threaderror(_, message)
    print("[thread] " .. tostring(message))
end

--- closing the window ends the session like quitting does
function love.quit()
    local state = StateManager.current
    if state and state.persist then state:persist() end
    Presence.shutdown()
    Stats.shutdown()
end

love.run = require("core.loop")
