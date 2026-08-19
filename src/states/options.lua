-- Settings screen with three tabs:
--   Audio     — volume sliders; apply live and persist immediately.
--   Interface — language/theme/title font/cursor/motion/stats sharing;
--               apply live and persist immediately, same as Audio.
--   Graphics  — resolution/display mode/vsync; changes accumulate in a
--               `pending` table and only take effect (and persist) on Apply.
--               Leaving the screen discards pending.
--
-- Esc or "Back" returns to whichever state opened this one:
--   StateManager.fadeTo("options", { returnTo = "pause" })
--
-- Abandoning a run isn't offered here: during a run this screen is reached
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
local GameTitle = require "ui.text.gameTitle"

local HEADING_Y_RATIO = 0.12
local PANEL_Y_RATIO   = 0.32 -- preferred start; pulled up if the stack wouldn't fit, see Options:layout
local PANEL_PAD       = 20   -- design-space px, scaled through Theme.px
local PANEL_MAX_W     = 560

-- seconds before an unconfirmed graphics change reverts on its own -- a mode
-- the monitor can't display leaves the player unable to click a revert button
local REVERT_SECONDS = 10

local RESOLUTIONS = { {1024, 768}, {1280, 720}, {1440, 1080}, {1600, 900}, {1680, 1050}, {1920, 1080} }

local MSAA = Settings.MSAA_LEVELS -- owned by Settings; conf.lua validates against the same list at boot

-- selector order; display names come from options.windowMode.<mode> in the locale
local WINDOW_MODES = { "windowed", "borderless", "exclusive" }

local Options = {}

-- index of the first entry `matches` accepts, or 1 -- a saved value no
-- longer on offer (a resolution the monitor lost) falls back to the first option
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

local function titleFontIndexFor(id)
    return indexWhere(GameTitle.available(), function(e) return e.id == id end)
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

-- keeps derived enabled-states in sync with pending; call after any mutation
-- of `pending`. Resolution row is inert in borderless (always desktop res
-- there); Apply greys out when there's nothing to apply.
function Options:syncEnabledStates()
    self.resolutionSelector.enabled = self.pending.windowMode ~= "borderless"
    self.applyButton.enabled = self:isDirty()
    self.group:refresh() -- move focus off a row that just went inert
end

function Options:isDirty()
    return self.pending.resIndex ~= resolutionIndexFor(self.settings)
        or self.pending.msaa ~= self.settings.msaa
        or self.pending.windowMode ~= self.settings.windowMode
        or self.pending.vsync ~= self.settings.vsync
end

-- resets pending graphics changes to the live settings and syncs widget
-- displays (setting fields directly never fires onChange)
function Options:resetPending()
    local msaaIndex = msaaIndexFor(self.settings)
    self.pending = {
        resIndex = resolutionIndexFor(self.settings),
        msaa = MSAA[msaaIndex], -- the sample count itself, not an index, unlike resIndex (a resolution is a pair)
        windowMode = self.settings.windowMode,
        vsync = self.settings.vsync,
    }
    self.resolutionSelector.index = self.pending.resIndex
    self.msaaSelector.index = msaaIndex
    self.windowModeSelector.index = windowModeIndexFor(self.pending.windowMode)
    self.vsyncToggle.value = self.pending.vsync == 1
    self:syncEnabledStates()
end

function Options:graphicsSnapshot()
    return {
        res_x = self.settings.res_x,
        res_y = self.settings.res_y,
        msaa = self.settings.msaa,
        windowMode = self.settings.windowMode,
        vsync = self.settings.vsync,
    }
end

-- commits pending: settings <- pending, apply, then ask the player to
-- confirm before persisting -- nothing hits disk until they do, since an
-- unusable mode must not survive a restart
function Options:applyPending()
    if not self:isDirty() then return end

    self.revertTo = self:graphicsSnapshot()

    local res = RESOLUTIONS[self.pending.resIndex]
    self.settings.res_x, self.settings.res_y = res[1], res[2]
    self.settings.msaa = self.pending.msaa
    self.settings.windowMode = self.pending.windowMode
    self.settings.vsync = self.pending.vsync

    Settings.applyGraphics(self.settings)
    -- re-read, not just re-check dirtiness: applyGraphics writes back the
    -- msaa the driver actually granted, which can be lower than requested
    self:resetPending()
    self.revertDialog:openDialog()
end

function Options:keepGraphics()
    self.revertDialog:close()
    self.revertTo = nil
    Settings.save(self.settings)

    -- they were already leaving when they chose Apply (see buildDialogs), so
    -- a confirmed change carries them the rest of the way out
    if self.leaveAfterApply then
        self.leaveAfterApply = false
        self:leave()
    end
end

-- declined, or the countdown ran out (the case that matters: it's what a
-- player who can't see anything is relying on)
function Options:revertGraphics()
    self.revertDialog:close()
    self.leaveAfterApply = false -- the mode didn't stick, so any queued exit is dropped
    if not self.revertTo then return end

    for key, value in pairs(self.revertTo) do
        self.settings[key] = value
    end
    self.revertTo = nil

    Settings.applyGraphics(self.settings)
    self:resetPending()
end

-- switches the UI palette and rebuilds the one thing that can't just re-read
-- it: the nebula stamps accent colors into its canvases at bake time, so it
-- keeps the old theme's hues until re-baked. Shared instance from Assets, so
-- this also recolors the main menu's copy.
function Options:applyTheme(id)
    if not UI.Theme.setTheme(id) then return end

    local nebula = Assets.get("nebula")
    if nebula and nebula:isBaked() then nebula:bake() end
end

-- both layout and the focus list read this, so a footer button can never be
-- visible-but-unfocusable or vice versa
function Options:footerButtons()
    return { self.backButton }
end

-- Back/Esc: graphics edits only take effect on Apply, and the greyed-out
-- Apply button isn't much of a reminder that edits are outstanding, so
-- leaving with pending edits asks first.
function Options:goBack()
    UI.Sfx.select()
    if self:isDirty() then
        self.unappliedDialog:openDialog()
        return
    end
    self:leave()
end

function Options:leave()
    StateManager.fadeTo(self.returnTo)
end

-- Music passes blip = false: it retunes live and is already its own preview,
-- so an sfx click on top would demo the wrong channel. i18n key, description
-- key and settings field are all `key` by construction.
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

function Options:buildDialogs()
    local blip = UI.Sfx.focus

    -- the countdown is the whole point: if the new mode is unreadable, doing
    -- nothing has to be the safe choice
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

    -- raised by Back/Esc when graphics edits are still pending; cancelling
    -- keeps the player here with the edits intact
    self.unappliedDialog = UI.Dialog.new{
        title = function() return I18n.t("dialog.unapplied.title") end,
        message = function() return I18n.t("dialog.unapplied.message") end,
        onCancel = function() self.unappliedDialog:close() end,
        buttons = {
            -- discard first, matching the revert dialog's "commits nothing" order
            { label = function() return I18n.t("dialog.unapplied.discard") end,
              danger = true,
              onSelect = function()
                  self.unappliedDialog:close()
                  self:resetPending()
                  self:leave()
              end },
            { label = function() return I18n.t("dialog.unapplied.apply") end,
              onSelect = function()
                  self.unappliedDialog:close()
                  -- applyPending raises the revert countdown, so the exit
                  -- waits on the player confirming the new mode works
                  self.leaveAfterApply = true
                  self:applyPending()
              end },
        },
    }

    self.revertDialog:setFocusSound(blip)
    self.unappliedDialog:setFocusSound(blip)
end

function Options:activeDialog()
    if self.revertDialog and self.revertDialog:isOpen() then return self.revertDialog end
    if self.unappliedDialog and self.unappliedDialog:isOpen() then return self.unappliedDialog end
    return nil
end

-- rebuilds the focus list for the active tab: tab bar, then the tab's
-- widgets, then footer buttons -- drives both focus order and layout below
function Options:selectTab(index)
    self.activeTab = index
    self.tabBar.index = index -- direct field set never fires onChange, so no recursion

    local widgets = { self.tabBar }
    for _, widget in ipairs(self.tabs[index].widgets) do
        widgets[#widgets + 1] = widget
    end
    for _, button in ipairs(self:footerButtons()) do
        widgets[#widgets + 1] = button
    end
    self.group:setWidgets(widgets)

    self:layout() -- a different tab has a different row count
end

-- lines the description area needs: the longest description in this tab,
-- wrapped to the panel width. Measured over the whole tab, not the focused
-- row, so the panel doesn't jump every time focus lands on a wordier row.
local DESC_MAX_LINES = 3 -- caps one runaway string from squeezing the rows it describes; draw clips past this

function Options:descriptionLines(width)
    local font = UI.Theme.font("small")
    local most = 1

    for _, widget in ipairs(self.tabs[self.activeTab].widgets) do
        if widget.descKey then
            local _, wrapped = font:getWrap(I18n.t(widget.descKey), width)
            most = math.max(most, #wrapped)
        end
    end
    -- the resolution row's inert-state line isn't any widget's descKey
    if self.tabs[self.activeTab].name == "graphics" then
        local _, wrapped = font:getWrap(I18n.t("options.desc.resolutionBorderless"), width)
        most = math.max(most, #wrapped)
    end

    return math.min(most, DESC_MAX_LINES)
end

-- Computes every rect this screen draws. Called on enter/resize/tab switch,
-- never from draw -- hit-testing reads these bounds, and laying out during
-- draw meant input for a frame was answered against the previous geometry.
--
-- Laid out to FIT rather than a fixed pose: every row scales with window
-- height via Theme.metrics, so a taller window just draws bigger rows, not
-- more of them -- the stack ran off the bottom at every resolution once
-- General reached seven rows (worse on big screens: 1920x1080 overshot by
-- 71px vs 39px at 1024x768). So: measure the space between heading and hint
-- line and shrink to fit, whitespace first and row height only if that's not
-- enough (a full-height row with less air still reads as a control; a
-- squashed one stops looking clickable).
function Options:layout()
    local w, h = love.graphics.getDimensions()
    local m = UI.Theme.metrics

    local rows = #self.tabs[self.activeTab].widgets
    local footer = self:footerButtons()
    local panelW = math.min(UI.Theme.px(PANEL_MAX_W), w * 0.72)
    local panelX = (w - panelW) / 2

    local descH = UI.Theme.font("small"):getHeight()
        * self:descriptionLines(panelW - UI.Theme.px(PANEL_PAD) * 2)

    -- tab bar + tab rows + footer buttons are all one row tall, with a gap after each but the last
    local rowCount = 1 + rows + #footer
    local gapCount = rows + #footer + 1
    local function stackHeight(rowH, gap, pad)
        return rowCount * rowH + gapCount * gap + pad * 2 + descH
    end

    local headingBottom = h * HEADING_Y_RATIO + UI.Theme.font("heading"):getHeight()
    local stackTop = headingBottom + m.rowGap
    local budget = UI.Label.hintY() - m.rowGap - stackTop

    -- floors derived from the font, not hardcoded, so a row can't shrink past its own label
    local minRow = UI.Theme.font("body"):getHeight() + UI.Theme.px(8)
    local minGap = UI.Theme.px(4)
    local minPad = UI.Theme.px(6)

    local rowH, gap, pad = m.rowHeight, m.rowGap, UI.Theme.px(PANEL_PAD)

    if stackHeight(rowH, gap, pad) > budget then
        -- whitespace first, all of it proportionally, down to the floors
        local slack = gapCount * (gap - minGap) + 2 * (pad - minPad)
        local need = stackHeight(rowH, gap, pad) - budget
        if slack > 0 then
            local keep = 1 - math.min(need, slack) / slack
            gap = minGap + math.floor((gap - minGap) * keep)
            pad = minPad + math.floor((pad - minPad) * keep)
        end

        -- then, only then, the rows themselves
        if stackHeight(rowH, gap, pad) > budget then
            local forRows = budget - gapCount * gap - pad * 2 - descH
            rowH = math.max(minRow, math.floor(forRows / rowCount))
        end
    end

    local panelH = pad * 2 + rows * rowH + (rows - 1) * gap
    local stackH = stackHeight(rowH, gap, pad)

    -- preferred pose, clamped so the whole stack stays inside the budget
    local aboveH = rowH + gap -- tab bar and its gap
    local top = math.max(stackTop,
        math.min(h * PANEL_Y_RATIO - aboveH, stackTop + budget - stackH))
    local panelY = top + aboveH

    self.panel = { x = panelX, y = panelY, w = panelW, h = panelH }

    self.tabBar:setBounds(panelX, panelY - rowH - gap, panelW, rowH)

    for i, widget in ipairs(self.tabs[self.activeTab].widgets) do
        widget:setBounds(
            panelX + pad,
            panelY + pad + (i - 1) * (rowH + gap),
            panelW - pad * 2,
            rowH)
    end

    for i, button in ipairs(footer) do
        button:setBounds(
            panelX,
            panelY + panelH + gap + (i - 1) * (rowH + gap),
            panelW,
            rowH)
    end

    -- height is the reserved one, so draw can tell whether it reaches the hint line
    local footerBottom = panelY + panelH + gap + #footer * (rowH + gap)
    self.descRect = { x = panelX, y = footerBottom, w = panelW, h = descH }

    if self.revertDialog then self.revertDialog:layout() end
    if self.unappliedDialog then self.unappliedDialog:layout() end
end

function Options:resize()
    self:layout()
end

-- resolution row gets a different line when inert, since "greyed out with no reason" is the confusion to avoid
function Options:focusedDescription()
    local widget = self.group:focused()
    if not widget or not widget.descKey then return nil end
    if widget == self.resolutionSelector and not widget.enabled then
        return "options.desc.resolutionBorderless"
    end
    return widget.descKey
end

-- StateManager calls enter(previousName, ...); opts.returnTo wins, else
-- wherever we came from. Guard stops Options targeting itself if re-entered.
function Options:enter(previousName, opts)
    Presence.set{ details = "Options", state = "Changing settings",
                    smallText = "Options", startedAt = Globals.game.startedAt }
    self.returnTo = StateManager.returnTarget(previousName, opts, "options")

    self.settings = Assets.get("settings") or Settings.load()

    self.mouseX, self.mouseY = love.mouse.getPosition()

    if not self.group then
        self.group = UI.FocusGroup.new()
        self.group.onFocusChanged = UI.Sfx.focus
    end

    local function persist()
        Settings.save(self.settings)
    end

    if not self.tabs then
        -- labels are functions so they re-read the active language every
        -- draw -- changing language updates the screen live, no rebuild

        -- Audio tab: all three sliders apply live and persist immediately.
        -- Master scales every channel via love.audio.setVolume; Music/SFX
        -- are independent channels (core/audio.lua).
        self.volumeSlider = self:buildVolumeSlider("volume", love.audio.setVolume, true)
        self.musicVolumeSlider = self:buildVolumeSlider("musicVolume",
            function(v) Audio.setVolume("music", v) end, false)
        self.sfxVolumeSlider = self:buildVolumeSlider("sfxVolume",
            function(v) Audio.setVolume("sfx", v) end, true)

        -- Interface tab: language/theme/title font/cursor/motion/stats
        -- sharing, all live and persisted immediately, same as Audio.
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

        -- live and persisted immediately too: unlike a resolution a palette
        -- can't leave the player unable to see the screen
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

        -- also live/immediate: a font swap can't strand the player either,
        -- and only touches the wordmark, so nothing else needs a rebuild
        self.titleFontSelector = UI.Selector.new{
            label = function() return I18n.t("options.titleFont") end,
            options = GameTitle.available(),
            format = function(entry) return I18n.t("options.titleFontName." .. entry.id) end,
            onChange = function(entry)
                UI.Sfx.select()
                self.settings.titleFont = entry.id
                GameTitle.setFont(entry.id)
                persist()
            end,
        }
        self.titleFontSelector.descKey = 'options.desc.titleFont'

        -- live/immediate too; UI.Cursor owns actually swapping the OS
        -- pointer back in, this just tells it to
        self.customCursorToggle = UI.Toggle.new{
            label = function() return I18n.t("options.customCursor") end,
            value = self.settings.customCursor,
            onChange = function(value)
                UI.Sfx.select()
                self.settings.customCursor = value
                UI.Cursor.setEnabled(value)
                persist()
            end,
        }
        self.customCursorToggle.descKey = 'options.desc.customCursor'

        -- live/immediate; UI.Motion is the one thing every ambient-animation
        -- module reads to dampen itself, see ui/core/motion.lua
        self.reducedMotionToggle = UI.Toggle.new{
            label = function() return I18n.t("options.reducedMotion") end,
            value = self.settings.reducedMotion,
            onChange = function(value)
                UI.Sfx.select()
                self.settings.reducedMotion = value
                UI.Motion.setReduced(value)
                persist()
            end,
        }
        self.reducedMotionToggle.descKey = 'options.desc.reducedMotion'

        -- a privacy switch that waited for a restart wouldn't really be one
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

        self.applyButton = UI.Button.new{
            label = function() return I18n.t("options.apply") end,
            onSelect = function()
                UI.Sfx.press()
                self:applyPending()
            end,
        }
        self.applyButton.descKey = 'options.desc.apply'

        -- reads self.returnTo when clicked rather than capturing it, since
        -- this block only runs on the first visit
        self.backButton = UI.Button.new{
            label = function() return I18n.t("options.back") end,
            onSelect = function() self:goBack() end,
        }
        self.backButton.descKey = 'options.desc.back'

        self:buildDialogs()

        self.tabs = {
            { name = "audio",     widgets = { self.volumeSlider, self.musicVolumeSlider,
                                               self.sfxVolumeSlider, } },
            { name = "interface", widgets = { self.languageSelector, self.themeSelector,
                                               self.titleFontSelector, self.customCursorToggle,
                                               self.reducedMotionToggle, self.shareStatsToggle, } },
            { name = "graphics",  widgets = { self.resolutionSelector, self.msaaSelector, self.windowModeSelector,
                                               self.vsyncToggle, self.applyButton, } },
        }

        self.tabBar = UI.TabBar.new{
            tabs = {
                function() return I18n.t("options.tab.audio") end,
                function() return I18n.t("options.tab.interface") end,
                function() return I18n.t("options.tab.graphics") end,
            },
            onChange = function(_, index)
                UI.Sfx.select()
                self:selectTab(index)
            end,
        }
    end

    -- a fresh visit never inherits an open modal
    self.revertDialog:close()
    self.unappliedDialog:close()
    self.revertTo = nil
    self.leaveAfterApply = false

    self.volumeSlider.value = self.settings.volume
    self.musicVolumeSlider.value = self.settings.musicVolume
    self.sfxVolumeSlider.value = self.settings.sfxVolume
    self.languageSelector.index = languageIndexFor(self.settings.language)
    self.themeSelector.index = themeIndexFor(UI.Theme.current)
    self.titleFontSelector.index = titleFontIndexFor(GameTitle.current)
    self.customCursorToggle.value = self.settings.customCursor
    self.reducedMotionToggle.value = self.settings.reducedMotion
    self.shareStatsToggle.value = self.settings.shareStats
    self:resetPending()
    self:selectTab(self.tabBar.index)
end

-- a modal owns every input while open; the screen behind keeps drawing but
-- stops responding. Dialog exposes the same verbs FocusGroup does, so
-- routing is just a choice of receiver.
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

-- written out, not routed: a modal's own Esc cancels the modal, only an unmodal screen leaves
function Options:keypressed(key)
    local dialog = self:activeDialog()
    if dialog then return dialog:keypressed(key) end
    if key == "escape" then return self:goBack() end
    return self.group:keypressed(key)
end

function Options:draw()
    local h = love.graphics.getHeight()
    local panel = self.panel

    UI.Label.draw{
        text = I18n.t("options.title"),
        y = h * HEADING_Y_RATIO,
        font = UI.Theme.font("heading"),
    }

    -- tab bar and footer sit outside the panel, tab rows inside it, so
    -- drawing happens in three passes rather than through the focus group's own draw
    self.tabBar:draw()

    UI.Theme.panel(panel.x, panel.y, panel.w, panel.h)

    for _, widget in ipairs(self.tabs[self.activeTab].widgets) do
        widget:draw()
    end
    for _, button in ipairs(self:footerButtons()) do
        button:draw()
    end

    local desc = self.descRect
    local descKey = self:focusedDescription()
    if descKey then
        -- clipped to the reserved height; the scissor only matters if a
        -- future string exceeds DESC_MAX_LINES
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

    -- description and hint share one line at the bottom; the tallest stack
    -- leaves room for only one, and description (about the focused row) wins
    if desc.y + desc.h <= UI.Label.hintY() then
        local onGraphics = self.tabs[self.activeTab].name == "graphics"
        UI.Label.hint(I18n.t(onGraphics and "options.hint.graphics" or "options.hint.general"))
    end

    local dialog = self:activeDialog()
    if dialog then dialog:draw() end

    local overWidget, dangerous = self:inputTarget():hovering(self.mouseX or -1, self.mouseY or -1)
    UI.Cursor.setHover(self.mouseX ~= nil and overWidget, dangerous)
end

return Options
