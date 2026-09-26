--- The play screen. Gameplay isn't designed yet, so today a run is just its
-- start time (Discord's elapsed timer), the game playlist and the pause menu --
-- the way a run reaches Achievements and Options, which both return here paused.

local StateManager = require "core.stateManager"
local Presence = require "services.presence"
local UI = require "ui"
local I18n = require "core.i18n"

local HEADING_Y_RATIO = 0.22
local MENU_Y_RATIO = 0.38

-- screens the pause menu opens; arriving back from one resumes the run paused
local PAUSE_DESTINATIONS = { options = true, achievements = true }

local InGame = {}

---@param previousName string|nil
function InGame:enter(previousName)
    local resuming = PAUSE_DESTINATIONS[previousName] == true and self.runStartedAt ~= nil
    if not resuming then
        self.runStartedAt = os.time()
    end
    Presence.show("game", { startedAt = self.runStartedAt })
    UI.Music.start("game")

    self.mouseX, self.mouseY = love.mouse.getPosition()
    self:buildPauseMenu()
    self.paused = resuming
    self:layout()
end

function InGame:buildPauseMenu()
    if self.pauseMenu then return end

    local function open(name)
        UI.Sfx.select()
        StateManager.fadeTo(name, { returnTo = "game" })
    end

    self.pauseMenu = UI.Menu.new{
        { label = function() return I18n.t("game.pause.resume") end, primary = true,
          onSelect = function() self:setPaused(false) end },
        { label = function() return I18n.t("menu.achievements") end,
          onSelect = function() open("achievements") end },
        { label = function() return I18n.t("menu.options") end,
          onSelect = function() open("options") end },
        { label = function() return I18n.t("game.pause.quit") end, danger = true,
          onSelect = function() self:quitRun() end },
    }
    self.pauseMenu:onFocusChanged(UI.Sfx.focus)
end

---@param paused boolean
function InGame:setPaused(paused)
    if paused == self.paused then return end
    UI.Sfx.select()
    self.paused = paused
    if paused then
        self.pauseMenu:setFocus(1, true)
        self:layout()
    end
end

--- ends the run; the next Play starts a fresh one
function InGame:quitRun()
    UI.Sfx.select()
    self.runStartedAt = nil
    StateManager.fadeTo("mainMenu")
end

function InGame:layout()
    self.pauseMenu:layout(love.graphics.getHeight() * MENU_Y_RATIO)
end

function InGame:resize()
    self:layout()
end

---@param dt number
function InGame:update(dt)
    if self.paused then self.pauseMenu:update(dt) end
end

--- losing window focus mid-run pauses it, so alt-tabbing away doesn't leave
-- the game running unattended once there's something to run
---@param focused boolean
function InGame:focus(focused)
    if not focused then self:setPaused(true) end
end

---@param key string
function InGame:keypressed(key)
    if key == "escape" then
        self:setPaused(not self.paused)
        return
    end
    if self.paused then self.pauseMenu:keypressed(key) end
end

---@param x number
---@param y number
function InGame:mousemoved(x, y)
    self.mouseX, self.mouseY = x, y
    if self.paused then self.pauseMenu:mousemoved(x, y) end
end

---@param x number
---@param y number
---@param button integer
function InGame:mousepressed(x, y, button)
    if self.paused then self.pauseMenu:mousepressed(x, y, button) end
end

---@param x number
---@param y number
---@param button integer
function InGame:mousereleased(x, y, button)
    if self.paused then self.pauseMenu:mousereleased(x, y, button) end
end

function InGame:draw()
    if not self.paused then
        UI.Label.hint(I18n.t("game.hint"))
        UI.Cursor.setHover(false)
        return
    end

    UI.Theme.setColor(UI.Theme.colors.scrim)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())
    love.graphics.setColor(1, 1, 1, 1)

    UI.Label.draw{
        text = I18n.t("game.pause.title"),
        y = love.graphics.getHeight() * HEADING_Y_RATIO,
        font = UI.Theme.font("heading"),
        shadow = true,
    }
    self.pauseMenu:draw()
    UI.Label.hint(I18n.t("game.pause.hint"), true)

    local overWidget, dangerous = self.pauseMenu:hovering(self.mouseX or -1, self.mouseY or -1)
    UI.Cursor.setHover(self.mouseX ~= nil and overWidget, dangerous)
end

return InGame
