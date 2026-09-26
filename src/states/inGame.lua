--- The play screen. Today it's only the shell a run lives in: Discord's elapsed
-- timer, the game playlist and the pause overlay -- the way a run reaches
-- Achievements and Options, which both return here paused.

local StateManager = require "core.stateManager"
local Presence = require "services.presence"
local UI = require "ui"
local I18n = require "core.i18n"
local Ease = require "utils.ease"

-- design-space px, scaled through Theme.px at use
local PANEL_PAD = 28
local HEADING_GAP = 14
local DIVIDER_W = 64
local MENU_GAP = 20
local SLIDE = 16

local FADE_SPEED = 7 -- overlay reaches full in ~0.15s

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
    self.quitDialog:close()
    self.paused = resuming
    self.overlay = resuming and 1 or 0
    self:layout()
end

function InGame:buildPauseMenu()
    if self.pauseMenu then return end

    local function open(name)
        UI.Sfx.select()
        StateManager.fadeTo(name, { returnTo = "game" })
    end

    self.pauseMenu = UI.Menu.new{
        { label = function() return I18n.t("game.pause.resume") end, icon = "play", primary = true,
          onSelect = function() self:setPaused(false) end },
        { label = function() return I18n.t("menu.achievements") end, icon = "trophy",
          onSelect = function() open("achievements") end },
        { label = function() return I18n.t("menu.options") end, icon = "gear",
          onSelect = function() open("options") end },
        { label = function() return I18n.t("game.pause.quit") end, icon = "quit", danger = true,
          onSelect = function()
              UI.Sfx.select()
              self.quitDialog:openDialog()
          end },
    }
    self.pauseMenu:onFocusChanged(UI.Sfx.focus)

    -- Cancel is listed first so a reflexive Enter doesn't throw the run away
    self.quitDialog = UI.Dialog.new{
        title = function() return I18n.t("game.pause.confirmQuit.title") end,
        message = function() return I18n.t("game.pause.confirmQuit.message") end,
        buttons = {
            { label = function() return I18n.t("dialog.cancel") end,
              onSelect = function() self.quitDialog:close() end },
            { label = function() return I18n.t("game.pause.quit") end, danger = true,
              onSelect = function() self:quitRun() end },
        },
    }
    self.quitDialog:setFocusSound(UI.Sfx.focus)
end

---@param paused boolean
function InGame:setPaused(paused)
    if paused == self.paused then return end
    UI.Sfx.select()
    self.paused = paused
    self.quitDialog:close()
    if paused then
        self.pauseMenu:setFocus(1, true)
        self:layout()
    end
end

--- ends the run; the next Play starts a fresh one
function InGame:quitRun()
    UI.Sfx.select()
    self.quitDialog:close()
    self.runStartedAt = nil
    StateManager.fadeTo("mainMenu")
end

--- the panel wraps the heading, a divider and the menu, centred on screen
function InGame:layout()
    local m = UI.Theme.metrics
    local px = UI.Theme.px
    local w, h = love.graphics.getDimensions()
    local buttons = self.pauseMenu:buttons()

    local headingH = UI.Theme.font("heading"):getHeight()
    local menuH = #buttons * m.rowHeight + (#buttons - 1) * m.rowGap
    local pad = px(PANEL_PAD)
    local panelH = pad * 2 + headingH + px(HEADING_GAP) * 2 + px(MENU_GAP) + menuH
    local top = math.floor((h - panelH) / 2)

    local menuY = top + pad + headingH + px(HEADING_GAP) * 2 + px(MENU_GAP)
    self.pauseMenu:layout(menuY)

    local menuW = buttons[1].w
    local panelW = math.max(menuW + pad * 2, UI.Theme.font("heading"):getWidth(I18n.t("game.pause.title")) + pad * 2)
    self.panel = { x = math.floor((w - panelW) / 2), y = top, w = panelW, h = panelH }
    self.headingY = top + pad
    self.dividerY = self.headingY + headingH + px(HEADING_GAP)

    self.quitDialog:layout()
end

function InGame:resize()
    self:layout()
end

---@param dt number
function InGame:update(dt)
    self.overlay = UI.Theme.approach(self.overlay, self.paused and 1 or 0, dt, FADE_SPEED)
    if not self.paused then return end

    if self.quitDialog:isOpen() then
        self.quitDialog:update(dt)
    else
        self.pauseMenu:update(dt)
    end
end

--- losing window focus mid-run pauses it, so alt-tabbing away doesn't leave
-- the game running unattended once there's something to run
---@param focused boolean
function InGame:focus(focused)
    if not focused then self:setPaused(true) end
end

---@param key string
function InGame:keypressed(key)
    if self.paused and self.quitDialog:isOpen() then
        self.quitDialog:keypressed(key)
        return
    end
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
    if not self.paused then return end
    if self.quitDialog:isOpen() then
        self.quitDialog:mousemoved(x, y)
    else
        self.pauseMenu:mousemoved(x, y)
    end
end

---@param x number
---@param y number
---@param button integer
function InGame:mousepressed(x, y, button)
    if not self.paused then return end
    if self.quitDialog:isOpen() then
        self.quitDialog:mousepressed(x, y, button)
    else
        self.pauseMenu:mousepressed(x, y, button)
    end
end

---@param x number
---@param y number
---@param button integer
function InGame:mousereleased(x, y, button)
    if not self.paused then return end
    if self.quitDialog:isOpen() then
        self.quitDialog:mousereleased(x, y, button)
    else
        self.pauseMenu:mousereleased(x, y, button)
    end
end

function InGame:drawPauseOverlay()
    local c = UI.Theme.colors
    local alpha = Ease.outCubic(self.overlay)
    local offset = UI.Motion.reduced and 0 or UI.Theme.px(SLIDE) * (1 - alpha)

    UI.Theme.setColor(c.scrim, (c.scrim[4] or 1) * alpha)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())

    love.graphics.push()
    love.graphics.translate(0, offset)

    local p, radius = self.panel, UI.Theme.metrics.radius
    UI.Theme.setColor(c.panel, (c.panel[4] or 1) * alpha)
    love.graphics.rectangle("fill", p.x, p.y, p.w, p.h, radius, radius, 8)
    UI.Theme.setColor(c.panelBorder, (c.panelBorder[4] or 1) * alpha)
    love.graphics.rectangle("line", p.x, p.y, p.w, p.h, radius, radius, 8)

    UI.Label.draw{
        text = I18n.t("game.pause.title"),
        y = self.headingY,
        font = UI.Theme.font("heading"),
        alpha = alpha,
        shadow = true,
    }

    local dividerW = UI.Theme.px(DIVIDER_W)
    UI.Theme.setColor(c.accent, alpha)
    love.graphics.rectangle("fill", (love.graphics.getWidth() - dividerW) / 2, self.dividerY,
        dividerW, math.max(1, UI.Theme.px(2)))

    for _, button in ipairs(self.pauseMenu:buttons()) do button.introAlpha = alpha end
    self.pauseMenu:draw()

    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)
end

function InGame:draw()
    if self.overlay > 0.001 then self:drawPauseOverlay() end

    if not self.paused then
        UI.Cursor.setHover(false)
        return
    end

    UI.Label.hint(I18n.t("game.pause.hint"), true)

    local mx, my = self.mouseX or -1, self.mouseY or -1
    local overWidget, dangerous
    if self.quitDialog:isOpen() then
        self.quitDialog:draw()
        overWidget, dangerous = self.quitDialog:hovering(mx, my)
    else
        overWidget, dangerous = self.pauseMenu:hovering(mx, my)
    end
    UI.Cursor.setHover(self.mouseX ~= nil and overWidget, dangerous)
end

return InGame
