-- src/states/options.lua
-- Settings screen with two tabs:
--   General  — volume slider; applies live and persists immediately.
--   Graphics — resolution / display mode / vsync; changes accumulate in a
--              `pending` table and only take effect (and persist) when the
--              Apply button is pressed. Leaving the screen discards pending.
--
-- Esc or "Back" returns to whichever state opened this one:
--
--   StateManager.fadeTo("options", { returnTo = "pause" })
--
-- Abandoning a run is not offered here: during a run this screen is reached
-- through the pause menu, and that's where quitting lives.

local StateManager = require "core.stateManager"
local Assets = require "core.assets"
local Settings = require "core.settings"
local UI = require "ui"
local I18n = require "core.i18n"
local Audio = require "core.audio"
local Presence = require "services.presence"
local Stats = require "services.stats"
local Globals = require "globals"

local HEADING_Y_RATIO = 0.12
-- Where the panel would like to start. It's pulled upward from here when the
-- stack below it wouldn't otherwise fit — see Options:layout.
local PANEL_Y_RATIO   = 0.32
-- Design-space px, scaled through Theme.px at use.
local PANEL_PAD       = 20
local PANEL_MAX_W     = 560

-- How long the player has to confirm a graphics change before it reverts on its
-- own. A resolution or fullscreen mode the monitor can't display leaves them
-- unable to see, let alone click, a revert button — so the game has to do it.
local REVERT_SECONDS = 10

local RESOLUTIONS = { {1024, 768}, {1280, 720}, {1440, 1080}, {1600, 900}, {1680, 1050}, {1920, 1080} }

-- Owned by Settings, not this screen: conf.lua has to validate against the same
-- list at boot (see the comment there). A driver may grant fewer samples than
-- asked for — Settings.applyGraphics writes back what it actually got.
local MSAA = Settings.MSAA_LEVELS

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

local function themeIndexFor(id)
    return indexWhere(UI.Theme.available(), function(e) return e.id == id end)
end

local function resolutionIndexFor(settings)
    return indexWhere(RESOLUTIONS, function(r)
        return r[1] == settings.res_x and r[2] == settings.res_y
    end)
end

local function msaaIndexFor(settings)
    return indexWhere(MSAA, function(s) return s == settings.msaa end)
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
        or self.pending.msaa ~= self.settings.msaa
        or self.pending.windowMode ~= self.settings.windowMode
        or self.pending.vsync ~= self.settings.vsync
end

-- Resets pending graphics changes back to the live settings and syncs the
-- widget displays (setting fields directly never fires onChange).
function Options:resetPending()
    -- Both the pending value and the selector's position come from the same
    -- index, so they can never disagree. That matters for a saved msaa we don't
    -- offer (an older build wrote an index here, and a driver can grant an
    -- off-list count): the row falls back to the first option and Apply lights
    -- up, which is the player's way out, rather than displaying one thing while
    -- pending holds another.
    local msaaIndex = msaaIndexFor(self.settings)
    self.pending = {
        resIndex = resolutionIndexFor(self.settings),
        -- The sample count itself, not an index — like windowMode and vsync,
        -- and unlike resIndex, which has to stay an index because a resolution
        -- is a pair.
        msaa = MSAA[msaaIndex],
        windowMode = self.settings.windowMode,
        vsync = self.settings.vsync,
    }
    self.resolutionSelector.index = self.pending.resIndex
    self.msaaSelector.index = msaaIndex
    self.windowModeSelector.index = windowModeIndexFor(self.pending.windowMode)
    self.vsyncToggle.value = self.pending.vsync == 1
    self:syncEnabledStates()
end

-- A copy of the graphics settings currently in effect, for reverting to.
function Options:graphicsSnapshot()
    return {
        res_x = self.settings.res_x,
        res_y = self.settings.res_y,
        msaa = self.settings.msaa,
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
    self.settings.msaa = self.pending.msaa
    self.settings.windowMode = self.pending.windowMode
    self.settings.vsync = self.pending.vsync

    Settings.applyGraphics(self.settings)
    -- Re-read rather than just re-checking dirtiness: applyGraphics writes back
    -- the msaa the driver actually granted, which can be lower than what was
    -- asked for. Without this the selector would keep showing the request, and
    -- Apply would stay lit forever because pending never matches settings.
    self:resetPending()
    self.revertDialog:openDialog()
end

-- Player confirmed the new mode is usable: now it's safe to persist.
function Options:keepGraphics()
    self.revertDialog:close()
    self.revertTo = nil
    Settings.save(self.settings)

    -- They were already on their way out when they chose Apply (see
    -- buildDialogs), so a change that's now confirmed carries them the rest of
    -- the way rather than parking them back on a screen they'd finished with.
    if self.leaveAfterApply then
        self.leaveAfterApply = false
        self:leave()
    end
end

-- Player declined, or the countdown ran out (which is the case that matters —
-- it's what a player who can't see anything is relying on).
function Options:revertGraphics()
    self.revertDialog:close()
    -- The mode they picked didn't stick, so any exit queued behind it is
    -- dropped: they stay here, where they can try a different one.
    self.leaveAfterApply = false
    if not self.revertTo then return end

    for key, value in pairs(self.revertTo) do
        self.settings[key] = value
    end
    self.revertTo = nil

    Settings.applyGraphics(self.settings)
    self:resetPending()
end

-- Switches the UI palette and rebuilds the one thing that can't simply re-read
-- it. Everything drawn from Theme.colors picks the new palette up on its next
-- frame — but the nebula stamps its gas into canvases with the accent colors
-- burnt in at bake time, so the backdrop would keep the old theme's hues until
-- something else forced a bake. It's the shared instance from Assets, so
-- re-baking it here also recolors the copy the main menu is holding.
function Options:applyTheme(id)
    if not UI.Theme.setTheme(id) then return end

    local nebula = Assets.get("nebula")
    if nebula and nebula:isBaked() then nebula:bake() end
end

-- Buttons stacked under the panel, in draw order. Both the layout and the focus
-- list read this, so a footer button can never be visible-but-unfocusable (or
-- vice versa) — which is why it stays a list for the one button there is today.
function Options:footerButtons()
    return { self.backButton }
end

-- Back, or Esc. Graphics edits only take effect on Apply, so walking away from
-- them is the one action on this screen that silently throws work out — and the
-- Apply button greying itself out once it's been pressed is not much of a
-- reminder that it hasn't been. So leaving with edits outstanding asks first.
function Options:goBack()
    UI.Sfx.select()
    if self:isDirty() then
        self.unappliedDialog:openDialog()
        return
    end
    self:leave()
end

-- The actual exit, for whichever state opened this screen. Anything still
-- pending is dropped here (resetPending on the next visit); by this point the
-- player has been asked about it.
function Options:leave()
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
            { label = function() return I18n.t("dialog.revert.revert") end, danger = true,
              onSelect = function() self:revertGraphics() end },
            { label = function() return I18n.t("dialog.revert.keep") end,
              onSelect = function() self:keepGraphics() end },
        },
    }

    -- Raised by Back/Esc when graphics edits are still pending. Cancelling
    -- (Esc, or a click off the panel) keeps the player here with the edits
    -- intact, so the way out of this prompt is never the way that loses them.
    self.unappliedDialog = UI.Dialog.new{
        title = function() return I18n.t("dialog.unapplied.title") end,
        message = function() return I18n.t("dialog.unapplied.message") end,
        onCancel = function() self.unappliedDialog:close() end,
        buttons = {
            -- Discard first, matching the revert dialog's "the option that
            -- commits nothing comes first" order.
            { label = function() return I18n.t("dialog.unapplied.discard") end,
              danger = true,
              onSelect = function()
                  self.unappliedDialog:close()
                  self:resetPending() -- drop the edits, then go
                  self:leave()
              end },
            { label = function() return I18n.t("dialog.unapplied.apply") end,
              onSelect = function()
                  self.unappliedDialog:close()
                  -- applyPending raises the revert countdown, so the exit waits
                  -- on the player confirming the new mode is actually usable.
                  self.leaveAfterApply = true
                  self:applyPending()
              end },
        },
    }

    self.revertDialog:setFocusSound(blip)
    self.unappliedDialog:setFocusSound(blip)
end

-- The modal currently showing, if any. Everything routes around this.
function Options:activeDialog()
    if self.revertDialog and self.revertDialog:isOpen() then return self.revertDialog end
    if self.unappliedDialog and self.unappliedDialog:isOpen() then return self.unappliedDialog end
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
-- Lines the description area has to be able to hold: the longest description in
-- this tab, wrapped to the panel width. Measured over the whole tab rather than
-- over the focused row, so the stack is a property of the tab and the panel
-- doesn't jump every time the focus moves onto a wordier setting.
--
-- Capped, because one runaway string shouldn't be able to squeeze the rows it
-- is describing; a description longer than the cap is clipped by draw instead.
local DESC_MAX_LINES = 3

function Options:descriptionLines(width)
    local font = UI.Theme.font("small")
    local most = 1

    for _, widget in ipairs(self.tabs[self.activeTab].widgets) do
        if widget.descKey then
            local _, wrapped = font:getWrap(I18n.t(widget.descKey), width)
            most = math.max(most, #wrapped)
        end
    end
    -- The conditional line the resolution row shows while it's inert. It is
    -- never any widget's descKey, so nothing above would have measured it.
    if self.activeTab == 2 then
        local _, wrapped = font:getWrap(I18n.t("options.desc.resolutionBorderless"), width)
        most = math.max(most, #wrapped)
    end

    return math.min(most, DESC_MAX_LINES)
end

-- Computes every rect this screen draws and hands each widget its bounds.
-- Called on enter, on resize, and on tab switch — never from draw. Hit-testing
-- reads these bounds, so laying out during draw meant input for a frame was
-- answered against the *previous* frame's geometry.
--
-- The screen is laid out to FIT rather than to a fixed pose. Every row is sized
-- from Theme.metrics, which scales with the window height — so a taller window
-- buys no extra rows, it just draws the same rows bigger, and the stack ran off
-- the bottom at every supported resolution once the General tab reached seven
-- rows. Worse on big screens, not better: at 1920x1080 it overshot by 71px
-- against 39px at 1024x768.
--
-- So: measure the space actually available between the heading and the hint
-- line, and shrink to fit. Whitespace goes first and row height only if that
-- wasn't enough, because a full-height row with less air around it still reads
-- as a control while a squashed one stops looking clickable.
function Options:layout()
    local w, h = love.graphics.getDimensions()
    local m = UI.Theme.metrics

    local rows = #self.tabs[self.activeTab].widgets
    local footer = self:footerButtons()
    local panelW = math.min(UI.Theme.px(PANEL_MAX_W), w * 0.72)
    local panelX = (w - panelW) / 2

    local descH = UI.Theme.font("small"):getHeight()
        * self:descriptionLines(panelW - UI.Theme.px(PANEL_PAD) * 2)

    -- What the stack is made of, independent of how big each piece ends up:
    -- the tab bar, the tab's rows and the footer buttons are all one row tall,
    -- and a gap sits after every one of them except the last.
    local rowCount = 1 + rows + #footer
    local gapCount = rows + #footer + 1
    local function stackHeight(rowH, gap, pad)
        return rowCount * rowH + gapCount * gap + pad * 2 + descH
    end

    -- The room there is for it. Measured from under the heading to the hint
    -- line, which is the real ceiling and floor of this screen.
    local headingBottom = h * HEADING_Y_RATIO + UI.Theme.font("heading"):getHeight()
    local stackTop = headingBottom + m.rowGap
    local budget = UI.Label.hintY() - m.rowGap - stackTop

    -- Floors. Derived from the font rather than hardcoded, so a row can never
    -- be shorter than the label inside it however the type scale is retuned.
    local minRow = UI.Theme.font("body"):getHeight() + UI.Theme.px(8)
    local minGap = UI.Theme.px(4)
    local minPad = UI.Theme.px(6)

    local rowH, gap, pad = m.rowHeight, m.rowGap, UI.Theme.px(PANEL_PAD)

    if stackHeight(rowH, gap, pad) > budget then
        -- Whitespace first, all of it proportionally, down to the floors.
        local slack = gapCount * (gap - minGap) + 2 * (pad - minPad)
        local need = stackHeight(rowH, gap, pad) - budget
        if slack > 0 then
            local keep = 1 - math.min(need, slack) / slack
            gap = minGap + math.floor((gap - minGap) * keep)
            pad = minPad + math.floor((pad - minPad) * keep)
        end

        -- Then, and only then, the rows themselves.
        if stackHeight(rowH, gap, pad) > budget then
            local forRows = budget - gapCount * gap - pad * 2 - descH
            rowH = math.max(minRow, math.floor(forRows / rowCount))
        end
    end

    local panelH = pad * 2 + rows * rowH + (rows - 1) * gap
    local stackH = stackHeight(rowH, gap, pad)

    -- Preferred pose, clamped so the whole stack stays inside the budget. When
    -- it fits with room to spare this still sits where it always did.
    local aboveH = rowH + gap -- tab bar and its gap
    local top = math.max(stackTop,
        math.min(h * PANEL_Y_RATIO - aboveH, stackTop + budget - stackH))
    local panelY = top + aboveH

    self.panel = { x = panelX, y = panelY, w = panelW, h = panelH }

    -- Tab bar sits one row above the panel.
    self.tabBar:setBounds(panelX, panelY - rowH - gap, panelW, rowH)

    for i, widget in ipairs(self.tabs[self.activeTab].widgets) do
        widget:setBounds(
            panelX + pad,
            panelY + pad + (i - 1) * (rowH + gap),
            panelW - pad * 2,
            rowH)
    end

    -- Footer stack below the panel, full panel width, one row apart.
    for i, button in ipairs(footer) do
        button:setBounds(
            panelX,
            panelY + panelH + gap + (i - 1) * (rowH + gap),
            panelW,
            rowH)
    end

    -- Description for the focused row, under the last footer button. Its height
    -- is the reserved one, so draw can tell whether it reaches the hint line.
    local footerBottom = panelY + panelH + gap + #footer * (rowH + gap)
    self.descRect = { x = panelX, y = footerBottom, w = panelW, h = descH }

    if self.revertDialog then self.revertDialog:layout() end
    if self.unappliedDialog then self.unappliedDialog:layout() end
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
    Presence.set{ details = "Options", state = "Changing settings",
                    smallText = "Options", startedAt = Globals.game.startedAt }
    self.returnTo = StateManager.returnTarget(previousName, opts, "options")

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
        -- Music/SFX are independent channels (see src/core/audio.lua) so lowering
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

        -- Theme is General-tab behavior too: live and persisted immediately.
        -- Nothing is staged, because unlike a resolution a palette can't leave
        -- the player unable to see the screen — the worst case is a look they
        -- don't like, which the same selector undoes.
        self.themeSelector = UI.Selector.new{
            label = function() return I18n.t("options.theme") end,
            options = UI.Theme.available(),
            format = function(entry) return I18n.t("options.themeName." .. entry.id) end,
            onChange = function(entry)
                UI.Sfx.select()
                self.settings.theme = entry.id
                self:applyTheme(entry.id)
                persist()
            end,
        }
        self.themeSelector.descKey = 'options.desc.theme'

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

        self.msaaSelector = UI.Selector.new{
            label = function() return I18n.t("options.msaa") end,
            options = MSAA,
            format = function(samples)
                if samples == 0 then return I18n.t("options.msaaOff") end
                return samples .. "x"
            end,
            onChange = function(samples)
                UI.Sfx.select()
                self.pending.msaa = samples
                self:syncEnabledStates()
            end,
        }
        self.msaaSelector.descKey = 'options.desc.msaa'

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

        -- General-tab behavior: live and persisted immediately, like Language
        -- and Theme. setEnabled starts or stops the heartbeat thread on the
        -- spot — a privacy switch that only takes effect after a restart isn't
        -- really one.
        self.shareStatsToggle = UI.Toggle.new{
            label = function() return I18n.t("options.shareStats") end,
            value = self.settings.shareStats,
            onChange = function(value)
                UI.Sfx.select()
                self.settings.shareStats = value
                Stats.setEnabled(value)
                persist()
            end,
        }
        self.shareStatsToggle.descKey = 'options.desc.shareStats'

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

        self:buildDialogs()

        self.tabs = {
            { name = "general",  widgets = { self.volumeSlider, self.musicVolumeSlider,
                                             self.sfxVolumeSlider, self.languageSelector,
                                             self.themeSelector, self.shareStatsToggle, } },
            { name = "graphics", widgets = { self.resolutionSelector, self.msaaSelector, self.windowModeSelector,
                                             self.vsyncToggle, self.applyButton, } },
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
    self.revertDialog:close()
    self.unappliedDialog:close()
    self.revertTo = nil
    self.leaveAfterApply = false

    -- Fresh visit: discard any stale pending edits, re-sync live values.
    self.volumeSlider.value = self.settings.volume
    self.musicVolumeSlider.value = self.settings.musicVolume
    self.sfxVolumeSlider.value = self.settings.sfxVolume
    self.languageSelector.index = languageIndexFor(self.settings.language)
    self.themeSelector.index = themeIndexFor(UI.Theme.current)
    self.shareStatsToggle.value = self.settings.shareStats
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
    local desc = self.descRect
    local descKey = self:focusedDescription()
    if descKey then
        -- Clipped to the height layout reserved. That height is the longest
        -- description in this tab, so in practice nothing is cut — the scissor
        -- is here so that a future string longer than DESC_MAX_LINES loses its
        -- tail instead of spilling over the hint line and out of the window.
        love.graphics.setScissor(math.floor(desc.x), math.floor(desc.y),
            math.ceil(desc.w), math.ceil(desc.h))
        UI.Label.draw{
            text = I18n.t(descKey),
            x = desc.x,
            y = desc.y,
            width = desc.w,
            font = UI.Theme.font("small"),
            color = UI.Theme.colors.textMuted,
        }
        love.graphics.setScissor()
    end

    -- The description and the hint are both a single grey line at the bottom of
    -- the screen, and the tallest stack (a five-row tab with Quit in the footer)
    -- leaves room for only one of them. The description is about the row under
    -- the focus, so it wins; the static control hint is what gives way.
    if desc.y + desc.h <= UI.Label.hintY() then
        UI.Label.hint(I18n.t(self.activeTab == 2 and "options.hint.graphics" or "options.hint.general"))
    end

    -- Modals paint over everything, including the hint.
    local dialog = self:activeDialog()
    if dialog then dialog:draw() end

    UI.Cursor.setHover(self.mouseX ~= nil and self:inputTarget():hovering(self.mouseX, self.mouseY))
end

return Options
