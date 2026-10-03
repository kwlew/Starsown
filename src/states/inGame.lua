--- Play screen: engine, HUD, and the pause and death panels.

local DeathMenu = require("states.inGame.deathMenu")
local Engine = require("game.engine")
local Hud = require("game.hud")
local Music = require("core.audio.music")
local PauseMenu = require("states.inGame.pauseMenu")
local Pointer = require("states.shared.pointer")
local Presence = require("services.presence")
local StateManager = require("core.state.manager")
local UI = require("ui")

local InGame = {}

-- screens the pause menu opens; returning resumes paused
local PAUSE_DESTINATIONS = { options = true, achievements = true }

function InGame:build()
    self.pointer = Pointer.new()
    self.pause = PauseMenu.new{
        resume = function() self:setPaused(false) end,
        open = function(name)
            UI.Sfx.select()
            StateManager.fadeTo(name, { returnTo = "game" })
        end,
        quit = function() self:quitRun() end,
    }
    self.death = DeathMenu.new{
        respawn = function() self:respawn() end,
        quit = function() self:quitRun() end,
    }
end

---@param previousName string|nil
function InGame:enter(previousName)
    if not self.pause then self:build() end
    local resuming = PAUSE_DESTINATIONS[previousName] and self.runStartedAt ~= nil
    if not resuming then
        self.runStartedAt = os.time()
        self.engine = Engine.new()
        self.hud = Hud.new()
        self.death:setDead(false)
    end
    Presence.show("game", { startedAt = self.runStartedAt })
    Music.start("game")

    self.pointer:reset()
    self.paused = resuming
    self.pause:setOpen(resuming, true)
    self:layout()
end

function InGame:layout()
    self.pause:layout()
    self.death:layout()
end

---@param paused boolean
function InGame:setPaused(paused)
    if paused == self.paused or self.death.dead then return end
    UI.Sfx.select()
    self.paused = paused
    self.pause:setOpen(paused)
end

function InGame:respawn()
    UI.Sfx.select()
    self.engine:respawn()
    self.death:setDead(false)
end

--- ends the run; the next Play starts fresh
function InGame:quitRun()
    UI.Sfx.select()
    self.runStartedAt = nil
    StateManager.fadeTo("mainMenu")
end

---@return table|nil # whatever takes input over the world
function InGame:input()
    if self.death.dead then return self.death:input() end
    if self.paused then return self.pause:input() end
end

function InGame:resize()
    self:layout()
    self.engine:resize()
end

---@param dt number
function InGame:update(dt)
    self.pause:update(dt)
    self.death:update(dt)
    if not self.paused then
        self.engine:update(dt)
        self.hud:update(dt, self.engine.player)
        if not self.death.dead and self.engine:playerDead() then self.death:setDead(true) end
    end

    local input = self:input()
    if input then
        self.pointer:hover(input)
    elseif not self.death.dead then
        UI.Cursor.useGameCursor()
    end
end

--- alt-tabbing away pauses the run
---@param focused boolean
function InGame:focus(focused)
    if not focused then self:setPaused(true) end
end

---@param key string
function InGame:chordpressed(key)
    self.engine:chordpressed(key)
end

function InGame:keypressed(key)
    if self.death.dead then
        local input = self.death:input()
        if input then input:keypressed(key) end
        return
    end
    if self.paused and self.pause.quitDialog:isOpen() then return self.pause.quitDialog:keypressed(key) end
    if key == "escape" then return self:setPaused(not self.paused) end
    if self.paused then self.pause:input():keypressed(key) end
end

function InGame:mousemoved(x, y)
    self.pointer:move(x, y)
    local input = self:input()
    if input then input:mousemoved(x, y) end
end

function InGame:mousepressed(x, y, button)
    local input = self:input()
    if input then input:mousepressed(x, y, button) end
end

function InGame:mousereleased(x, y, button)
    local input = self:input()
    if input then input:mousereleased(x, y, button) end
end

function InGame:draw()
    self.engine:draw()
    self.hud:draw(self.engine.player)
    self.death:draw()
    self.pause:draw()
end

return InGame
