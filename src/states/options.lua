-- src/states/options.lua
-- Settings screen with two tabs:
--   General  — volume slider; applies live and persists immediately.
--   Graphics — resolution / display mode / vsync; changes accumulate in a
--              `pending` table and only take effect (and persist) when the
--              Apply button is pressed. Leaving the screen discards pending.
--
-- Esc or "Back" returns to whichever state opened this one:
--
--   StateManager.switch("options", { returnTo = "game" })
--
-- Opened from the game, the footer also grows a "Quit" button that abandons
-- the run and drops back to the main menu — from the main menu there's nothing
-- to quit back to, so it's hidden.

local StateManager = require "lib.stateManager"
local Assets = require "lib.assets"
local Settings = require "lib.settings"
local UI = require "lib.ui"
local I18n = require "lib.i18n"
local Audio = require "lib.audio"

local HEADING_Y_RATIO = 0.12
local PANEL_Y_RATIO   = 0.32
-- Design-space px, scaled through Theme.px at use.
local PANEL_PAD       = 20
local PANEL_MAX_W     = 560

-- How long the player has to confirm a graphics change before it reverts on its
-- own. A resolution or fullscreen mode the monitor can't display leaves them
-- unable to see, let alone click, a revert button — so the game has to do it.
local REVERT_SECONDS = 10

local RESOLUTIONS = { {1024, 768}, {1280, 720}, {1440, 1080}, {1600, 900}, {1680, 1050}, {1920, 1080} }

-- Window modes in selector order. Display names come from the active locale
-- (options.windowMode.<mode>): "Borderless" is desktop-type fullscreen,
-- "Fullscreen" is exclusive.
local WINDOW_MODES = { "windowed", "borderless", "exclusive" }

local Options = {}

-- Index of the first entry `matches` accepts, or 1 when nothing does. Every
-- selector here has to point at the saved value, and a saved value no longer on
-- offer (a resolution the monitor lost) falls back to the first option rather
-- than to nothing.
local function indexWhere(list, matches)
    for i, entry in ipairs(list) do
        if matches(entry) then return i end
    end
    return 1
end

local function languageIndexFor(code)
    return indexWhere(I18n.available(), function(e) return e.code == code end)
end

local function resolutionIndexFor(settings)
    return indexWhere(RESOLUTIONS, function(r)
        return r[1] == settings.res_x and r[2] == settings.res_y
    end)
end

local function windowModeIndexFor(mode)
    return indexWhere(WINDOW_MODES, function(name) return name == mode end)
end

-- Keeps derived enabled-states in sync with the pending graphics changes.
-- Call after any mutation of `pending`. Two rules:
--   * The resolution row is inert in borderless (the game always runs at the
--     desktop resolution there).
--   * The Apply button is greyed out when there's nothing to apply, so its
--     label can stay a constant "Apply" instead of changing text.
function Options:syncEnabledStates()
    self.resolutionSelector.enabled = self.pending.windowMode ~= "borderless"
    self.applyButton.enabled = self:isDirty()
    -- Applying is what greys Apply out, so the row under the focus can go inert
    -- beneath it; move focus along rather than leaving it on a dead control.
    self.group:refresh()
end

-- True when the graphics widgets differ from what's actually in effect.
function Options:isDirty()
    return self.pending.resIndex ~= resolutionIndexFor(self.settings)
        or self.pending.windowMode ~= self.settings.windowMode
        or self.pending.vsync ~= self.settings.vsync
end

-- Resets pending graphics changes back to the live settings and syncs the
-- widget displays (setting fields directly never fires onChange).
function Options:resetPending()
    self.pending = {
        resIndex = resolutionIndexFor(self.settings),
        windowMode = self.settings.windowMode,
        vsync = self.settings.vsync,
    }
    self.resolutionSelector.index = self.pending.resIndex
    self.windowModeSelector.index = windowModeIndexFor(self.pending.windowMode)
    self.vsyncToggle.value = self.pending.vsync == 1
    self:syncEnabledStates()
end

-- A copy of the graphics settings currently in effect, for reverting to.
function Options:graphicsSnapshot()
    return {
        res_x = self.settings.res_x,
        res_y = self.settings.res_y,
        windowMode = self.settings.windowMode,
        vsync = self.settings.vsync,
    }
end

-- Commits pending graphics changes: settings <- pending, apply, then ask the
-- player to confirm before persisting. Nothing is written to disk until they
-- do — an unusable mode must not survive a restart.
function Options:applyPending()
    if not self:isDirty() then return end

    self.revertTo = self:graphicsSnapshot()

    local res = RESOLUTIONS[self.pending.resIndex]
    self.settings.res_x, self.settings.res_y = res[1], res[2]
    self.settings.windowMode = self.pending.windowMode
    self.settings.vsync = self.pending.vsync

    Settings.applyGraphics(self.settings)
    self:syncEnabledStates() -- nothing left to apply -> grey the button out
    self.revertDialog:openDialog()
end

-- Player confirmed the new mode is usable: now it's safe to persist.
function Options:keepGraphics()
    self.revertDialog:close()
    self.revertTo = nil
    Settings.save(self.settings)
end

-- Player declined, or the countdown ran out (which is the case that matters —
-- it's what a player who can't see anything is relying on).
function Options:revertGraphics()
    self.revertDialog:close()
    if not self.revertTo then return end

    for key, value in pairs(self.revertTo) do
        self.settings[key] = value
    end
    self.revertTo = nil

    Settings.applyGraphics(self.settings)
    self:resetPending()
end

-- Buttons stacked under the panel, in draw order. Quit is only offered when
-- Options was opened from the game; entered from the main menu there's no run
-- to abandon. Both the layout and the focus list read this, so the button can
-- never be visible-but-unfocusable (or vice versa).
function Options:footerButtons()
    if self.returnTo == "game" then
        return { self.backButton, self.quitButton }
    end
    return { self.backButton }
end

-- Leaves for whichever state opened this screen. Pending graphics edits are
-- simply dropped (resetPending on the next visit).
function Options:goBack()
    UI.Sfx.select()
    StateManager.fadeTo(self.returnTo)
end

-- One of the three volume rows. They differ only in how the value reaches the
-- audio system and whether the release blips: Music passes blip = false because
-- it retunes live and is already its own preview, so an sfx click on top would
-- demo the wrong channel. The i18n key, description key and settings field are
-- all `key` by construction.
function Options:buildVolumeSlider(key, apply, blip)
    local slider = UI.Slider.new{
        label = function() return I18n.t("options." .. key) end,
        value = self.settings[key],
        step = 0.1,
        onChange = function(value) -- live, fires throughout a drag
            self.settings[key] = value
            apply(value)
        end,
        onRelease = function() -- final, fires when the change settles
            if blip then UI.Sfx.select() end
            Settings.save(self.settings)
        end,
    }
    slider.descKey = "options.desc." .. key
    return slider
end

-- The two modals this screen owns. Built once with the widgets.
function Options:buildDialogs()
    local blip = UI.Sfx.focus

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

    -- The countdown is the whole point: if the new mode is unreadable, doing
    -- nothing has to be the safe choice, so a timeout reverts.
    self.revertDialog = UI.Dialog.new{
        title = function() return I18n.t("dialog.revert.title") end,
        message = function(dialog)
            return I18n.t("dialog.revert.message",
                { n = math.max(0, math.ceil(dialog.remaining or 0)) })
        end,
        timeout = REVERT_SECONDS,
        onTimeout = function() self:revertGraphics() end,
        onCancel = function() self:revertGraphics() end,
        buttons = {
            { label = function() return I18n.t("dialog.revert.revert") end,
              onSelect = function() self:revertGraphics() end },
            { label = function() return I18n.t("dialog.revert.keep") end,
              onSelect = function() self:keepGraphics() end },
        },
    }

    self.quitDialog:setFocusSound(blip)
    self.revertDialog:setFocusSound(blip)
end

-- The modal currently showing, if any. Everything routes around this.
function Options:activeDialog()
    if self.quitDialog and self.quitDialog:isOpen() then return self.quitDialog end
    if self.revertDialog and self.revertDialog:isOpen() then return self.revertDialog end
    return nil
end

-- Rebuilds the focus list for the active tab: tab bar first, then the tab's
-- widgets, then the footer buttons. The list drives both focus order and the
-- layout below, so the two can never disagree about what's on screen.
function Options:selectTab(index)
    self.activeTab = index
    -- Keep the bar display in sync when switched programmatically (a direct
    -- field set never fires onChange, so no recursion).
    self.tabBar.index = index

    local widgets = { self.tabBar }
    for _, widget in ipairs(self.tabs[index].widgets) do
        widgets[#widgets + 1] = widget
    end
    for _, button in ipairs(self:footerButtons()) do
        widgets[#widgets + 1] = button
    end
    self.group:setWidgets(widgets)

    -- A different tab means a different number of rows, so the panel resizes.
    self:layout()
end

-- Computes every rect this screen draws and hands each widget its bounds.
-- Called on enter, on resize, and on tab switch — never from draw. Hit-testing
-- reads these bounds, so laying out during draw meant input for a frame was
-- answered against the *previous* frame's geometry.
function Options:layout()
    local w, h = love.graphics.getDimensions()
    local m = UI.Theme.metrics
    local pad = UI.Theme.px(PANEL_PAD)

    local rows = #self.tabs[self.activeTab].widgets
    local panelW = math.min(UI.Theme.px(PANEL_MAX_W), w * 0.72)
    local panelH = pad * 2 + rows * m.rowHeight + (rows - 1) * m.rowGap
    local panelX = (w - panelW) / 2
    local panelY = h * PANEL_Y_RATIO

    self.panel = { x = panelX, y = panelY, w = panelW, h = panelH }

    -- Tab bar sits one row above the panel.
    self.tabBar:setBounds(panelX, panelY - m.rowHeight - m.rowGap, panelW, m.rowHeight)

    for i, widget in ipairs(self.tabs[self.activeTab].widgets) do
        widget:setBounds(
            panelX + pad,
            panelY + pad + (i - 1) * (m.rowHeight + m.rowGap),
            panelW - pad * 2,
            m.rowHeight)
    end

    -- Footer stack below the panel, full panel width, one row apart.
    local footer = self:footerButtons()
    for i, button in ipairs(footer) do
        button:setBounds(
            panelX,
            panelY + panelH + m.rowGap + (i - 1) * (m.rowHeight + m.rowGap),
            panelW,
            m.rowHeight)
    end

    -- Description line for the focused row, under the last footer button.
    local footerBottom = panelY + panelH + m.rowGap + #footer * (m.rowHeight + m.rowGap)
    self.descRect = { x = panelX, y = footerBottom, w = panelW }

    if self.quitDialog then self.quitDialog:layout() end
    if self.revertDialog then self.revertDialog:layout() end
end

function Options:resize()
    self:layout()
end

-- Description key for the focused widget. The resolution row gets a different
-- line when it's inert, because "greyed out with no reason given" is exactly
-- the confusion this is here to fix.
function Options:focusedDescription()
    local widget = self.group:focused()
    if not widget or not widget.descKey then return nil end
    if widget == self.resolutionSelector and not widget.enabled then
        return "options.desc.resolutionBorderless"
    end
    return widget.descKey
end

-- StateManager calls enter(previousName, ...), so `opts` is whatever the
-- caller passed to switch(). An explicit opts.returnTo wins; otherwise we fall
-- back to the state we actually came from. The guard stops Options from
-- targeting itself if it's ever re-entered.
function Options:enter(previousName, opts)
    local returnTo = (type(opts) == "table" and opts.returnTo) or previousName
    if not returnTo or returnTo == "options" then returnTo = "mainMenu" end
    self.returnTo = returnTo

    -- Shared settings table, loaded and applied at boot by the loading state.
    self.settings = Assets.get("settings") or Settings.load()

    -- Seeded from the real pointer so hover feedback is right on the first
    -- frame, before the player moves the mouse again.
    self.mouseX, self.mouseY = love.mouse.getPosition()

    -- Owns focus order, keyboard navigation, and mouse routing (including the
    -- drag capture that keeps a slider tracking off-widget).
    if not self.group then
        self.group = UI.FocusGroup.new()
        self.group.onFocusChanged = UI.Sfx.focus
    end

    local function persist()
        Settings.save(self.settings)
    end

    if not self.tabs then
        -- Labels are functions (or format-time lookups) so they re-read the
        -- active language every draw — changing language updates the screen
        -- live, no rebuild.

        -- General tab: all three volume sliders apply live and persist
        -- immediately. Master scales every channel via love.audio.setVolume;
        -- Music/SFX are independent channels (see lib/audio.lua) so lowering
        -- one doesn't affect the other.
        self.volumeSlider = self:buildVolumeSlider("volume", love.audio.setVolume, true)
        self.musicVolumeSlider = self:buildVolumeSlider("musicVolume",
            function(v) Audio.setVolume("music", v) end, false)
        self.sfxVolumeSlider = self:buildVolumeSlider("sfxVolume",
            function(v) Audio.setVolume("sfx", v) end, true)

        -- Language also applies live and persists immediately (General-tab
        -- behavior, like Volume). Options are the {code, name} locale entries.
        self.languageSelector = UI.Selector.new{
            label = function() return I18n.t("options.language") end,
            options = I18n.available(),
            format = function(entry) return entry.name end,
            onChange = function(entry)
                UI.Sfx.select()
                self.settings.language = entry.code
                I18n.setLanguage(entry.code)
                persist()
            end,
        }
        self.languageSelector.descKey = 'options.desc.language'

        -- Graphics tab: writes to pending only; Apply commits.
        self.resolutionSelector = UI.Selector.new{
            label = function() return I18n.t("options.resolution") end,
            options = RESOLUTIONS,
            format = function(o) return o[1] .. "x" .. o[2] end,
            onChange = function(_, index)
                UI.Sfx.select()
                self.pending.resIndex = index
                self:syncEnabledStates()
            end,
        }
        self.resolutionSelector.descKey = 'options.desc.resolution'

        self.windowModeSelector = UI.Selector.new{
            label = function() return I18n.t("options.displayMode") end,
            options = WINDOW_MODES,
            format = function(mode) return I18n.t("options.windowMode." .. mode) end,
            onChange = function(mode)
                UI.Sfx.select()
                self.pending.windowMode = mode
                self:syncEnabledStates()
            end,
        }
        self.windowModeSelector.descKey = 'options.desc.displayMode'

        self.vsyncToggle = UI.Toggle.new{
            label = function() return I18n.t("options.vsync") end,
            onChange = function(value)
                UI.Sfx.select()
                self.pending.vsync = value and 1 or 0
                self:syncEnabledStates()
            end,
        }
        self.vsyncToggle.descKey = 'options.desc.vsync'

        -- Label is a constant "Apply"; the button greys out (via
        -- syncEnabledStates -> enabled = isDirty) when there's nothing to apply.
        self.applyButton = UI.Button.new{
            label = function() return I18n.t("options.apply") end,
            onSelect = function()
                UI.Sfx.press()
                self:applyPending()
            end,
        }
        self.applyButton.descKey = 'options.desc.apply'

        -- Both footer buttons are built once, like every other widget here,
        -- and read self.returnTo when clicked rather than capturing it — this
        -- block only runs on the first visit, so a captured value would pin
        -- every later visit to wherever Options was opened from first.
        self.backButton = UI.Button.new{
            label = function() return I18n.t("options.back") end,
            onSelect = function() self:goBack() end,
        }
        self.backButton.descKey = 'options.desc.back'

        -- Shown only when returnTo == "game" (see footerButtons). Abandoning a
        -- run is destructive, so it goes through a confirmation.
        self.quitButton = UI.Button.new{
            label = function() return I18n.t("options.quit") end,
            onSelect = function()
                UI.Sfx.press()
                self.quitDialog:openDialog()
            end,
        }
        self.quitButton.descKey = 'options.desc.quit'

        self:buildDialogs()

        self.tabs = {
            { name = "general",  widgets = { self.volumeSlider, self.musicVolumeSlider,
                                             self.sfxVolumeSlider, self.languageSelector } },
            { name = "graphics", widgets = { self.resolutionSelector, self.windowModeSelector,
                                             self.vsyncToggle, self.applyButton } },
        }

        self.tabBar = UI.TabBar.new{
            tabs = {
                function() return I18n.t("options.tab.general") end,
                function() return I18n.t("options.tab.graphics") end,
            },
            onChange = function(_, index)
                UI.Sfx.select()
                self:selectTab(index)
            end,
        }
    end

    -- Every exit path closes its own modal, but a modal left open would make
    -- this screen unusable, so a fresh visit never inherits one.
    self.quitDialog:close()
    self.revertDialog:close()
    self.revertTo = nil

    -- Fresh visit: discard any stale pending edits, re-sync live values.
    self.volumeSlider.value = self.settings.volume
    self.musicVolumeSlider.value = self.settings.musicVolume
    self.sfxVolumeSlider.value = self.settings.sfxVolume
    self.languageSelector.index = languageIndexFor(self.settings.language)
    self:resetPending()
    self:selectTab(self.tabBar.index)
end

-- A modal owns every input while it's up; the screen behind keeps drawing but
-- stops responding. Dialog presents the same verbs a FocusGroup does, so routing
-- is a choice of receiver rather than a branch per verb.
function Options:inputTarget()
    return self:activeDialog() or self.group
end

function Options:update(dt)            self:inputTarget():update(dt)            end
function Options:mousepressed(x, y, b) self:inputTarget():mousepressed(x, y, b) end
function Options:mousereleased(x, y, b) self:inputTarget():mousereleased(x, y, b) end

function Options:mousemoved(x, y)
    self.mouseX, self.mouseY = x, y
    self:inputTarget():mousemoved(x, y)
end

-- Written out rather than routed, because Esc sits between the two receivers: a
-- modal's own Esc cancels the modal, and only an unmodal screen leaves.
function Options:keypressed(key)
    local dialog = self:activeDialog()
    if dialog then return dialog:keypressed(key) end
    if key == "escape" then return self:goBack() end
    return self.group:keypressed(key)
end

-- Draw only. Every rect here was computed by Options:layout().
function Options:draw()
    local h = love.graphics.getHeight()
    local panel = self.panel

    UI.Label.draw{
        text = I18n.t("options.title"),
        y = h * HEADING_Y_RATIO,
        font = UI.Theme.font("heading"),
    }

    -- The tab bar and footer buttons sit outside the panel, the tab's rows
    -- inside it, so the widgets are drawn in three passes around it rather
    -- than through the focus group's own draw.
    self.tabBar:draw()

    UI.Theme.panel(panel.x, panel.y, panel.w, panel.h)

    for _, widget in ipairs(self.tabs[self.activeTab].widgets) do
        widget:draw()
    end
    for _, button in ipairs(self:footerButtons()) do
        button:draw()
    end

    -- What the focused row actually does. Also the only place the resolution
    -- selector can explain why it greys out in Borderless.
    local descKey = self:focusedDescription()
    if descKey then
        UI.Label.draw{
            text = I18n.t(descKey),
            x = self.descRect.x,
            y = self.descRect.y,
            width = self.descRect.w,
            font = UI.Theme.font("small"),
            color = UI.Theme.colors.textMuted,
        }
    end

    UI.Label.hint(I18n.t(self.activeTab == 2 and "options.hint.graphics" or "options.hint.general"))

    -- Modals paint over everything, including the hint.
    local dialog = self:activeDialog()
    if dialog then dialog:draw() end

    -- Asked for every frame the cursor is over an enabled control (see
    -- UI.Cursor for why this can't live in mousemoved).
    if self.mouseX and self:inputTarget():hovering(self.mouseX, self.mouseY) then
        UI.Cursor.want("hand")
    end
end

return Options
