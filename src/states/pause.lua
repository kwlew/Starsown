-- src/states/pause.lua
-- Pause screen. Esc during a run comes here rather than jumping straight to
-- Options, because this is the screen that owns the ways out of a run: resume
-- it, change settings, or abandon it.
--
-- It's a state like any other, but a *transparent* one. StateManager only ever
-- draws the current state, so this one draws the state it froze underneath
-- itself and dims it. Frozen means drawn but never updated — nothing in the run
-- ticks while this is up, which is the whole point of a pause menu.
--
--   StateManager.switch("pause")            -- from the run, instantly
--
-- Going to Options from here hands it `returnTo = "pause"`, so Back lands on
-- the pause menu with the run still frozen behind it. Options only grows its
-- own Quit button when it was opened straight from the game; reached this way
-- it doesn't, because the entry right here does that job.

local StateManager = require "core.stateManager"
local Presence = require "services.presence"
local Audio = require "core.audio"
local Menu = require "ui.menu"
local I18n = require "core.i18n"
local UI = require "ui"

local Pause = {}

-- Vertical anchors, as fractions of the window height.
local HEADING_Y_RATIO = 0.26
local MENU_Y_RATIO = 0.40

local function setPresence()
    Presence.set{ details = "Game Paused", state = "Paused in game",
                  smallText = "Paused" }
end

-- Back to the run. Instant rather than a fade: dissolving through black on the
-- way out of a pause menu puts a blackout between the player and the run they
-- just asked to continue.
function Pause:resume()
    UI.Sfx.select()
    StateManager.switch(self.pausedName, { resumed = true })
end

function Pause:openOptions()
    UI.Sfx.select()
    StateManager.fadeTo("options", { returnTo = "pause" })
end

-- Abandons the run. Destructive and unrecoverable, so it goes through a
-- confirmation, and the confirming button wears the danger tone.
function Pause:buildQuitDialog()
    self.quitDialog = UI.Dialog.new{
        title = function() return I18n.t("dialog.quit.title") end,
        message = function() return I18n.t("dialog.quit.message") end,
        onCancel = function() self.quitDialog:close() end,
        buttons = {
            { label = function() return I18n.t("dialog.cancel") end,
              onSelect = function() self.quitDialog:close() end },
            { label = function() return I18n.t("dialog.quit.confirm") end,
              danger = true,
              onSelect = function()
                  self.quitDialog:close()
                  Audio.stopAll() -- drop any gameplay audio on the way out
                  StateManager.fadeTo("mainMenu")
              end },
        },
    }
    self.quitDialog:setFocusSound(UI.Sfx.focus)
end

function Pause:enter(previousName, opts)
    setPresence()

    -- What we froze. A trip out to Options and back is a *return*, not a new
    -- pause, so the name we already hold wins over whoever we just came from;
    -- a caller can still name it outright via opts.paused.
    self.pausedName = (type(opts) == "table" and opts.paused)
        or self.pausedName or previousName or "game"
    self.paused = StateManager.get(self.pausedName)

    -- Seeded from the real pointer so hover feedback is right on the first
    -- frame back from Options, before the player moves the mouse again.
    self.mouseX, self.mouseY = love.mouse.getPosition()

    -- Built once: the menu is stateless between pauses, and labels are
    -- functions so they re-read the active language every draw (a language
    -- change made from Options updates this with no rebuild).
    if not self.menu then
        self.menu = Menu.new({
            { label = function() return I18n.t("pause.resume") end,
              onSelect = function() self:resume() end },
            { label = function() return I18n.t("pause.options") end,
              onSelect = function() self:openOptions() end },
            { label = function() return I18n.t("pause.quit") end, danger = true,
              onSelect = function()
                  UI.Sfx.press()
                  self.quitDialog:openDialog()
              end },
        })
        self.menu:onFocusChanged(UI.Sfx.focus)
        self:buildQuitDialog()
    end

    -- A modal left open would make this screen unusable, so a fresh pause never
    -- inherits one. Focus goes back to Resume, the reason most pauses end.
    self.quitDialog:close()
    self.menu:setFocus(1)

    self:layout()
end

function Pause:layout()
    local h = love.graphics.getHeight()
    self.menu:layout(h * MENU_Y_RATIO)
    self.quitDialog:layout()
end

-- Forwarded to the frozen state as well: it's still on screen behind this one,
-- and a resolution change made from Options (via Back to here) would otherwise
-- leave it drawing to the old window's layout.
function Pause:resize(w, h, rescaled)
    self:layout()
    if self.paused and self.paused.resize then
        self.paused:resize(w, h, rescaled)
    end
end

-- A modal owns every input while it's up; the menu behind keeps drawing but
-- stops responding. Dialog presents the same verbs a Menu does, so routing is a
-- choice of receiver rather than a branch per verb.
function Pause:inputTarget()
    if self.quitDialog:isOpen() then return self.quitDialog end
    return self.menu
end

-- Only the menu ticks. The frozen state is deliberately never updated — that is
-- what "paused" means here.
function Pause:update(dt)             self:inputTarget():update(dt)             end
function Pause:mousepressed(x, y, b)  self:inputTarget():mousepressed(x, y, b)  end
function Pause:mousereleased(x, y, b) self:inputTarget():mousereleased(x, y, b) end

function Pause:mousemoved(x, y)
    self.mouseX, self.mouseY = x, y
    self:inputTarget():mousemoved(x, y)
end

-- Written out rather than routed, because Esc sits between the two receivers: a
-- modal's own Esc cancels the modal, and only an unmodal pause screen resumes.
function Pause:keypressed(key)
    if self.quitDialog:isOpen() then return self.quitDialog:keypressed(key) end
    if key == "escape" then return self:resume() end
    return self.menu:keypressed(key)
end

function Pause:draw()
    local h = love.graphics.getHeight()

    -- The run is still what the player is looking at, so it keeps drawing. It
    -- just stopped moving.
    if self.paused and self.paused.draw then
        self.paused:draw()
    end

    -- Dimmed, so the menu on top is unmistakably the thing with focus.
    UI.Theme.setColor(UI.Theme.colors.scrim)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())

    -- Both shadowed: unlike every other screen's, this text sits directly on
    -- the run, and a bright tower or a lit path underneath would otherwise eat
    -- it. The menu itself doesn't need it — its rows are solid panels.
    UI.Label.draw{
        text = I18n.t("pause.title"),
        y = h * HEADING_Y_RATIO,
        font = UI.Theme.font("heading"),
        shadow = true,
    }

    self.menu:draw()
    UI.Label.hint(I18n.t("pause.hint"), true)

    -- The modal paints over everything, including the hint.
    if self.quitDialog:isOpen() then self.quitDialog:draw() end

    -- Asked for every frame the cursor is over an enabled control (see
    -- UI.Cursor for why this can't live in mousemoved).
    if self.mouseX and self:inputTarget():hovering(self.mouseX, self.mouseY) then
        UI.Cursor.want("hand")
    end
end

return Pause
