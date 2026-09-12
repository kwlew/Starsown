--- Settings screen with three tabs:
--   Audio     - volume sliders; apply live and persist immediately.
--   Interface - language/theme/title font/cursor/motion/stats sharing;
--               apply live and persist immediately, same as Audio.
--   Graphics  - resolution/display mode/vsync; changes accumulate in a
--               `pending` table and only take effect (and persist) on Apply.
--               Leaving with pending edits asks whether to apply or discard.
--
-- Esc or "Back" returns to whichever state opened this one:
--   StateManager.fadeTo("options", { returnTo = "pause" })
--
-- Abandoning a run isn't offered here: during a run this screen is reached
-- through the pause menu, and that's where quitting lives.

local StateManager = require "core.stateManager"
local Assets = require "core.assets"
local Settings = require "core.settings"
local FrameLimiter = require "core.frameLimiter"
local UI = require "ui"
local I18n = require "core.i18n"
local Audio = require "core.audio"
local Presence = require "services.presence"
local Stats = require "services.stats"
local Globals = require "globals"
local GameTitle = require "ui.text.gameTitle"
local ScrollArea = require "ui.widgets.scrollArea"
local DisplayLimits = require "core.displayLimits"

local PANEL_PAD = 10
local PANEL_MAX_W = 720

local REVERT_SECONDS = 10

local WINDOWED_FLOOR = { 1280, 720 } -- the one size always on offer if a desktop-size query ever fails
local DESKTOP_FRACTIONS = { 1, 0.75, 0.5 } -- of the selected display's desktop size, for windowed sizing

local MSAA = Settings.MSAA_LEVELS -- owned by Settings; conf.lua validates against the same list at boot

local WINDOW_MODES = { "windowed", "borderless", "exclusive" }

local Options = {}

---@return integer[] # 1..love.window.getDisplayCount(); LÖVE exposes no monitor names to label these with
local function displayOptions()
    local options = {}
    for i = 1, love.window.getDisplayCount() do options[i] = i end
    return options
end

--- exclusive fullscreen offers exactly the modes the display reports
-- (de-duplicated by size, largest first) -- getFullscreenModes is
-- specifically about fullscreen capability, so it's never used for the
-- windowed case below, which asks a different question entirely.
---@param display integer
---@return table[] # { {w, h}, ... }
local function exclusiveResolutions(display)
    local modes = love.window.getFullscreenModes(display)
    table.sort(modes, function(a, b)
        if a.width ~= b.width then return a.width > b.width end
        return a.height > b.height
    end)

    local minW, minH = DisplayLimits.minimum(display)
    local seen, list = {}, {}
    for _, mode in ipairs(modes) do
        local key = mode.width .. "x" .. mode.height
        if not seen[key] and mode.width >= minW and mode.height >= minH then
            seen[key] = true
            list[#list + 1] = { mode.width, mode.height }
        end
    end
    return list
end

--- windowed sizing is capped to the display's own desktop size rather than
-- offering anything getFullscreenModes reports -- a windowed size larger
-- than the desktop makes no more sense than a fullscreen mode the display
-- doesn't support. A monitor smaller than 1280x720 gets fractions of its own
-- (smaller) desktop instead of that floor -- see resolutionsFor, which only
-- falls back to WINDOWED_FLOOR if this returns nothing at all.
---@param display integer
---@return table[] # { {w, h}, ... }, largest first
local function windowedResolutions(display)
    local deskW, deskH = love.window.getDesktopDimensions(display)
    if type(deskW) ~= "number" or deskW <= 0 or deskH <= 0 then return {} end

    local minW, minH = DisplayLimits.minimum(display)
    local seen, list = {}, {}
    for _, fraction in ipairs(DESKTOP_FRACTIONS) do
        local w, h = math.max(minW, math.floor(deskW * fraction)), math.max(minH, math.floor(deskH * fraction))
        local key = w .. "x" .. h
        if not seen[key] and w > 0 and h > 0 then
            seen[key] = true
            list[#list + 1] = { w, h }
        end
    end
    return list
end

---@param display integer
---@param windowMode string
---@return table[] # { {w, h}, ... }; never empty
local function resolutionsFor(display, windowMode)
    local list = (windowMode == "exclusive") and exclusiveResolutions(display) or windowedResolutions(display)
    if #list == 0 then list[1] = WINDOWED_FLOOR end
    return list
end

--- index of the first entry `matches` accepts, or 1 -- a saved value no
-- longer on offer (a resolution the monitor lost) falls back to the first option
---@param list any[]
---@param matches fun(entry: any): boolean
---@return integer
local function indexWhere(list, matches)
    for i, entry in ipairs(list) do
        if matches(entry) then return i end
    end
    return 1
end

---@param code string
---@return integer
local function languageIndexFor(code)
    return indexWhere(I18n.available(), function(e) return e.code == code end)
end

---@param id string
---@return integer
local function themeIndexFor(id)
    return indexWhere(UI.Theme.available(), function(e) return e.id == id end)
end

---@param id string
---@return integer
local function titleFontIndexFor(id)
    return indexWhere(GameTitle.available(), function(e) return e.id == id end)
end

---@param display integer
---@return integer
local function displayIndexFor(display)
    return indexWhere(displayOptions(), function(n) return n == display end)
end

---@param settings table
---@return integer
local function msaaIndexFor(settings)
    return indexWhere(MSAA, function(s) return s == settings.msaa end)
end

---@param mode string
---@return integer
local function windowModeIndexFor(mode)
    return indexWhere(WINDOW_MODES, function(name) return name == mode end)
end

--- Only windowed modes may preserve custom sizes. A monitor/mode change
-- must not insert a resolution unsupported by the newly selected display.
function Options:rebuildResolutions(targetW, targetH)
    local mode, display = self.pending.windowMode, self.pending.display
    local options
    if mode == "borderless" then
        local w, h = love.window.getDesktopDimensions(display)
        options = { { w, h } }
    else options = resolutionsFor(display, mode) end
    local index
    for i, option in ipairs(options) do
        if option[1] == targetW and option[2] == targetH then index = i; break end
    end
    if not index and mode == "windowed" and targetW and targetH and targetW > 0 and targetH > 0 then
        local w, h = DisplayLimits.windowSize(targetW, targetH, display)
        local isLive = display == self.settings.display and mode == self.settings.windowMode
            and targetW == self.settings.res_x and targetH == self.settings.res_y
        if (w == targetW and h == targetH) or isLive then
            table.insert(options, 1, { targetW, targetH })
            index = 1
        end
    end
    if not index and mode == "exclusive" and display == self.settings.display
        and mode == self.settings.windowMode and targetW == self.settings.res_x and targetH == self.settings.res_y then
        table.insert(options, 1, { targetW, targetH }) -- the currently active mode is known to work
        index = 1
    end
    self.resolutionAdjusted = mode ~= "borderless" and not index and targetW and targetW > 0 or false
    self.resolutionSelector.options = options
    self.pending.resIndex = index or 1
    self.resolutionSelector.index = self.pending.resIndex
end

--- keeps derived enabled-states in sync with pending; call after any mutation
-- of `pending`. Resolution row is inert in borderless (always desktop res
-- there); Apply greys out when there's nothing to apply. Also re-derives the
-- resolution list, since a display or mode change (either lands here too)
-- can change which one applies.
function Options:syncEnabledStates()
    local current = self.resolutionSelector:selected()
    if self.pending.windowMode == "borderless" and self.resolutionMode ~= "borderless" then
        self.windowedResolution = current
    elseif self.resolutionMode == "borderless" and self.pending.windowMode ~= "borderless" then
        current = self.windowedResolution
    end
    self:rebuildResolutions(current and current[1] or -1, current and current[2] or -1)
    self.resolutionMode = self.pending.windowMode
    self.resolutionSelector.readOnly = self.pending.windowMode == "borderless"
    self.displaySelector.readOnly = #self.displaySelector.options == 1
    self.applyButton.enabled = self:isDirty()
    self.group:refresh() -- move focus off a row that just went inert
    if self.activeTab then self:layout() end
end

---@return boolean # whether Graphics has edits waiting on Apply
function Options:isDirty()
    local selected = self.resolutionSelector.options[self.pending.resIndex]
    return not selected
        or (self.pending.windowMode ~= "borderless"
            and (selected[1] ~= self.settings.res_x or selected[2] ~= self.settings.res_y))
        or self.pending.msaa ~= self.settings.msaa
        or self.pending.windowMode ~= self.settings.windowMode
        or self.pending.vsync ~= self.settings.vsync
        or self.pending.display ~= self.settings.display
end

--- resets pending graphics changes to the live settings and syncs widget
-- displays (setting fields directly never fires onChange)
function Options:resetPending()
    self.resolutionMode = nil
    self.displaySelector.options = displayOptions()
    local msaaIndex = msaaIndexFor(self.settings)
    self.pending = {
        display = self.settings.display,
        msaa = MSAA[msaaIndex], -- the sample count itself, not an index, unlike resIndex (a resolution is a pair)
        windowMode = self.settings.windowMode,
        vsync = self.settings.vsync,
    }
    self.displaySelector.index = displayIndexFor(self.pending.display)
    self.msaaSelector.index = msaaIndex
    self.windowModeSelector.index = windowModeIndexFor(self.pending.windowMode)
    self.vsyncToggle.value = self.pending.vsync == 1

    self:rebuildResolutions(self.settings.res_x, self.settings.res_y)
    self:syncEnabledStates()
end

---@return table # what applyPending saves so revertGraphics can put it back
function Options:graphicsSnapshot()
    return Settings.graphicsSnapshot(self.settings)
end

function Options:showGraphicsError(key)
    self.graphicsError = key
    self:openDialog(self.errorDialog)
end

function Options:applyPending()
    if not self:isDirty() then return end
    local ready = Settings.beginGraphicsPreview(self.settings)
    if not ready then return self:showGraphicsError("saveFailed") end
    self.revertTo = self:graphicsSnapshot()
    local res = self.resolutionSelector.options[self.pending.resIndex]
    self.settings.res_x, self.settings.res_y = res[1], res[2]
    self.settings.msaa, self.settings.windowMode = self.pending.msaa, self.pending.windowMode
    self.settings.vsync, self.settings.display = self.pending.vsync, self.pending.display
    local ok, _, adjusted = Settings.applyGraphics(self.settings)
    if not ok then
        local recovery = self:restoreGraphics()
        return self:showGraphicsError(recovery or "failed")
    end
    self.previewAdjusted = adjusted
    self:resetPending()
    self:openDialog(self.revertDialog)
end

function Options:keepGraphics()
    local ok = Settings.endGraphicsPreview(self.settings, true)
    if not ok then
        self.revertDialog:close()
        local recovery = self:restoreGraphics()
        return self:showGraphicsError(recovery or "saveFailed")
    end
    self.revertDialog:close()
    self.revertTo, self.previewAdjusted = nil, nil
    self:resetPending()
    if self.leaveAfterApply then self.leaveAfterApply = false; self:leave() end
end

-- If the old monitor disappeared, try a conservative window on the primary
-- display. Never replace the last confirmed file with an unconfirmed fallback.
function Options:restoreGraphics()
    self.leaveAfterApply = false
    local baseline = self.revertTo
    if not baseline then return end
    for key, value in pairs(baseline) do self.settings[key] = value end
    local ok = Settings.applyGraphics(self.settings)
    local recovery
    if not ok then
        self.settings.display, self.settings.windowMode = 1, "windowed"
        self.settings.res_x, self.settings.res_y = DisplayLimits.minimum(1)
        self.settings.msaa, self.settings.vsync = 0, 1
        ok = Settings.applyGraphics(self.settings)
        recovery = ok and "recovery" or "restoreFailed"
    end
    if not ok then Settings.readGraphics(self.settings) end
    Settings.endGraphicsPreview(self.settings, false)
    self.revertTo, self.previewAdjusted = nil, nil
    self:resetPending()
    return recovery
end

function Options:revertGraphics()
    self.revertDialog:close()
    local recovery = self:restoreGraphics()
    if recovery then self:showGraphicsError(recovery) end
end

--- switches the UI palette and rebuilds the one thing that can't just re-read
-- it: the nebula stamps accent colors into its canvases at bake time, so it
-- keeps the old theme's hues until re-baked. Shared instance from Assets, so
-- this also recolors the main menu's copy.
---@param id string
function Options:applyTheme(id)
    if not UI.Theme.setTheme(id) then return end

    local nebula = Assets.get("nebula")
    if nebula and nebula:isBaked() then nebula:bake() end
end

--- A disabled-at-boot nebula is intentionally not baked during loading. Pay
-- that one-time cost only if the player later asks to see it.
---@param value boolean
function Options:setNebulaVisible(value)
    local nebula = Assets.get("nebula")
    if not nebula then return end
    if value and not nebula:isBaked() then nebula:bake() end
    nebula.enabled = value
end

--- both layout and the focus list read this, so a footer button can never be
-- visible-but-unfocusable or vice versa
---@return table[]
function Options:footerButtons()
    return { self.backButton, self.applyButton }
end

--- Back/Esc: graphics edits only take effect on Apply, and the greyed-out
-- Apply button isn't much of a reminder that edits are outstanding, so
-- leaving with pending edits asks first.
function Options:goBack()
    UI.Sfx.select()
    if self:isDirty() then
        self:openDialog(self.unappliedDialog)
        return
    end
    self:leave()
end

--- fades back to whichever screen opened this one
function Options:leave()
    StateManager.fadeTo(self.returnTo)
end

--- Music passes blip = false: it retunes live and is already its own preview,
-- so an sfx click on top would demo the wrong channel. i18n key, description
-- key and settings field are all `key` by construction.
---@param key string # names the i18n string, the description key and the settings field
---@param apply fun(value: number) # applies the value live, throughout the drag
---@param blip boolean # play a click when the change settles
---@return table
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

--- Live/immediate toggles (most of Interface, plus the purely-cosmetic
-- Graphics rows like showNebula that can't strand the player the way a
-- resolution or fullscreen change can): apply and persist right away, same
-- contract as buildVolumeSlider above. i18n key, description key and
-- settings field are all `key` by construction; `sideEffect(value)`, if
-- given, is whatever beyond the settings write needs to happen (e.g.
-- UI.Cursor.setEnabled).
---@param key string # names the i18n string, the description key and the settings field
---@param sideEffect? fun(value: boolean)
---@return table
function Options:buildSettingToggle(key, sideEffect)
    local toggle = UI.Toggle.new{
        label = function() return I18n.t("options." .. key) end,
        value = self.settings[key],
        onChange = function(value)
            UI.Sfx.select()
            self.settings[key] = value
            if sideEffect then sideEffect(value) end
            Settings.save(self.settings)
        end,
    }
    toggle.descKey = "options.desc." .. key
    return toggle
end

--- Graphics-tab selectors: write into `pending` only and sync derived
-- enabled-states; Apply is what commits (see Options:applyPending). `key`
-- names both the i18n string and the widget itself; `pendingKey` is the
-- field written on `pending`, since it isn't always the same name (the
-- displayMode row's pending field is `windowMode`). `valueOf(option, index)`
-- picks what actually gets stored -- defaults to the option itself, but the
-- resolution row stores the index instead (see rebuildResolutions -- its
-- list is rebuilt live as the display/mode selectors change, so an index
-- into it, not the pair itself, is what stays meaningful in `pending`).
---@param key string # names the i18n string and description key
---@param options any[]
---@param format fun(option: any): string
---@param pendingKey string # the field written on `pending`
---@param valueOf? fun(option: any, index: integer): any # defaults to the option itself
---@return table
function Options:buildPendingSelector(key, options, format, pendingKey, valueOf)
    valueOf = valueOf or function(option) return option end
    local selector = UI.Selector.new{
        label = function() return I18n.t("options." .. key) end,
        options = options,
        format = format,
        onChange = function(option, index)
            UI.Sfx.select()
            self.pending[pendingKey] = valueOf(option, index)
            self:syncEnabledStates()
        end,
    }
    selector.descKey = "options.desc." .. key
    return selector
end

--- Graphics-tab toggle (currently just VSync); same pending/sync contract as
-- buildPendingSelector above. `transform`, if given, converts the widget's
-- boolean into whatever `pending[pendingKey]` actually stores.
---@param key string # names the i18n string and description key
---@param pendingKey string # the field written on `pending`
---@param transform? fun(value: boolean): any
---@return table
function Options:buildPendingToggle(key, pendingKey, transform)
    transform = transform or function(value) return value end
    local toggle = UI.Toggle.new{
        label = function() return I18n.t("options." .. key) end,
        onChange = function(value)
            UI.Sfx.select()
            self.pending[pendingKey] = transform(value)
            self:syncEnabledStates()
        end,
    }
    toggle.descKey = "options.desc." .. key
    return toggle
end

--- the two prompts this screen owns: the countdown that auto-reverts an
-- applied graphics change, and the one that catches leaving with edits
-- outstanding
function Options:buildDialogs()
    local blip = UI.Sfx.focus

    self.revertDialog = UI.Dialog.new{
        title = function() return I18n.t("dialog.revert.title") end,
        fontRole = "help",
        message = function(dialog)
            local text = I18n.t("dialog.revert.message", { n = math.max(0, math.ceil(dialog.remaining or 0)) })
            if self.previewAdjusted then
                local v = self.settings
                text = text .. "\n\n" .. I18n.t("options.adjustedGraphics") .. "\n"
                    .. I18n.t("options.displayOption", { n = v.display }) .. " · "
                    .. I18n.t("options.windowMode." .. v.windowMode) .. " · " .. v.res_x .. "×" .. v.res_y
                    .. "\n" .. I18n.t("options.msaa") .. ": "
                    .. (v.msaa == 0 and I18n.t("options.msaaOff") or v.msaa .. "x")
                    .. " · VSync: " .. I18n.t(v.vsync == 0 and "options.state.off" or "options.state.on")
            end
            return text
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

    self.unappliedDialog = UI.Dialog.new{
        title = function() return I18n.t("dialog.unapplied.title") end,
        message = function() return I18n.t("dialog.unapplied.message") end,
        onCancel = function() self.unappliedDialog:close() end,
        buttons = {
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
                  self.leaveAfterApply = true
                  self:applyPending()
              end },
        },
    }

    self.errorDialog = UI.Dialog.new{
        title = function() return I18n.t("options.errorTitle") end,
        message = function() return I18n.t("options.error." .. (self.graphicsError or "failed")) end,
        fontRole = "help",
        buttons = { { label = function() return I18n.t("dialog.close") end,
            onSelect = function() self.errorDialog:close() end } },
    }
    self.errorDialog:setFocusSound(blip)
    self.revertDialog:setFocusSound(blip)
    self.unappliedDialog:setFocusSound(blip)
end

---@return table|nil # the open dialog, if either is
function Options:activeDialog()
    for _, dialog in ipairs({ self.revertDialog, self.unappliedDialog, self.errorDialog }) do
        if dialog:isOpen() then return dialog end
    end
    return nil
end

--- rebuilds the focus list for the active tab: tab bar, then the tab's
-- widgets, then footer buttons -- drives both focus order and layout below
---@param index integer
function Options:selectTab(index)
    if self.scroll and self.activeTab then
        self.tabs[self.activeTab].scrollY = self.scroll.targetY
        self.scroll.dragOffset = nil
    end
    self.group:releaseCapture()
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

    self:layout(self.tabs[index].scrollY or 0)
end

--- Fixed regions are measured first; only the setting rows consume overflow.
function Options:layout(scrollY)
    if not self.activeTab then return end
    local w, h = love.graphics.getDimensions()
    local theme, m = UI.Theme, UI.Theme.metrics
    local margin, gap, pad = theme.px(24), theme.px(10), theme.px(PANEL_PAD)
    local panelW = math.min(theme.px(PANEL_MAX_W), w - margin * 2)
    local panelX = (w - panelW) / 2
    local small, buttonFont = theme.font("small"), theme.font("button")
    local function textHeight(font, text, width)
        local _, lines = font:getWrap(text, width)
        return math.max(1, #lines) * font:getHeight()
    end

    self.headingY = margin

    local tabH = m.rowHeight
    local segmentW = (panelW - theme.px(6) * 2) / 3
    for _, name in ipairs(self.tabBar.tabs) do
        tabH = math.max(tabH, textHeight(buttonFont, theme.resolveLabel(name, self.tabBar), segmentW) + theme.px(12))
    end
    local tabY = self.headingY + theme.font("heading"):getHeight() + gap
    self.tabBar:setBounds(panelX, tabY, panelW, tabH)

    local hintH = textHeight(small, I18n.t("options.hint.navigation"), panelW)
    self.hintRect = { x = panelX, y = h - theme.px(16) - hintH, w = panelW, h = hintH }
    local buttonW = (panelW - m.rowGap) / 2
    local footerH = m.rowHeight
    for _, button in ipairs(self:footerButtons()) do
        footerH = math.max(footerH, textHeight(buttonFont, button:labelText(), buttonW) + theme.px(12))
    end
    local footerY = self.hintRect.y - gap - footerH
    for i, button in ipairs(self:footerButtons()) do
        button:setBounds(panelX + (i - 1) * (buttonW + m.rowGap), footerY, buttonW, footerH)
    end
    local statusH = textHeight(small, I18n.t("options.pendingGraphics"), panelW)
    self.statusRect = { x = panelX, y = footerY - gap - statusH, w = panelW, h = statusH }

    local panelY = tabY + tabH + gap
    local panelH = math.max(1, self.statusRect.y - gap - panelY)
    local scrollW = panelW - pad * 2
    local widgets = self.tabs[self.activeTab].widgets
    self.scroll:layout(widgets, panelX + pad, panelY + pad, scrollW, math.max(1, panelH - pad * 2), scrollY)
    self.panel = { x = panelX, y = panelY, w = panelW, h = panelH }
    self.layoutLanguage = I18n.current
    self.baselineWidth, self.baselineHeight = self.settings.res_x, self.settings.res_y
    if self.revertDialog then self.revertDialog:layout() end
    if self.unappliedDialog then self.unappliedDialog:layout() end
    if self.errorDialog then self.errorDialog:layout() end
end

function Options:resize()
    -- A user window drag updates live settings before this callback. Preserve
    -- explicit pending resolution edits, but let an untouched resolution follow
    -- the new window size without creating a false Apply state.
    if self.pending and self.settings.windowMode == "windowed" and not self.revertTo then
        local selected = self.resolutionSelector:selected()
        if selected and selected[1] == self.baselineWidth and selected[2] == self.baselineHeight then
            self:rebuildResolutions(self.settings.res_x, self.settings.res_y)
            self.applyButton.enabled = self:isDirty()
            self.group:refresh()
        end
    end
    self:layout()
    if self.keyboardInput then self:revealFocus() end
end

function Options:revealFocus(smooth)
    self.scroll:reveal(self.group:focused(), smooth)
end

--- StateManager calls enter(previousName, ...); opts.returnTo wins, else
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
        self.scroll = ScrollArea.new()
        self.group.pointerFilter = function(widget, x, y)
            return self.scroll:allowsPointer(widget, x, y)
        end
    end

    --- writes the live settings out; the immediate-apply rows call this directly
    local function persist()
        Settings.save(self.settings)
    end

    if not self.tabs then

        self.volumeSlider = self:buildVolumeSlider("volume", love.audio.setVolume, true)
        self.musicVolumeSlider = self:buildVolumeSlider("musicVolume",
            function(v) Audio.setVolume("music", v) end, false)
        self.sfxVolumeSlider = self:buildVolumeSlider("sfxVolume",
            function(v) Audio.setVolume("sfx", v) end, true)

        self.languageSelector = UI.Selector.new{
            label = function() return I18n.t("options.language") end,
            options = I18n.available(),
            format = function(entry) return entry.name end,
            onChange = function(entry)
                UI.Sfx.select()
                self.settings.language = entry.code
                I18n.setLanguage(entry.code)
                self:layout()
                persist()
            end,
        }
        self.languageSelector.descKey = 'options.desc.language'

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
        self.themePreview = UI.Preview.newTheme{}

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
        self.titleFontPreview = UI.Preview.newTitleFont{}

        self.customCursorToggle = self:buildSettingToggle("customCursor", UI.Cursor.setEnabled)

        self.reducedMotionToggle = self:buildSettingToggle("reducedMotion", UI.Motion.setReduced)

        self.shareStatsToggle = self:buildSettingToggle("shareStats", Stats.setEnabled)

        -- A read-only row's reason has to live in the value text itself, not
        -- the shared description below: keyboard/mouse focus both skip
        -- non-interactive widgets, so a row that can never be focused can
        -- never surface an explanation that depends on being focused first.
        self.displaySelector = self:buildPendingSelector("display", displayOptions(),
            function(n)
                local text = I18n.t("options.displayOption", { n = n })
                if self.displaySelector and self.displaySelector.readOnly then
                    text = text .. " · " .. I18n.t("options.note.monitor")
                end
                return text
            end,
            "display")

        self.resolutionSelector = self:buildPendingSelector("resolution",
            resolutionsFor(self.settings.display, self.settings.windowMode),
            function(o)
                local text = o[1] .. "x" .. o[2]
                if self.resolutionSelector and self.resolutionSelector.readOnly then
                    text = text .. " · " .. I18n.t("options.note.borderless")
                end
                return text
            end,
            "resIndex", function(_, index) return index end)

        self.msaaSelector = self:buildPendingSelector("msaa", MSAA,
            function(samples)
                if samples == 0 then return I18n.t("options.msaaOff") end
                return samples .. "x"
            end,
            "msaa")

        self.windowModeSelector = self:buildPendingSelector("displayMode", WINDOW_MODES,
            function(mode) return I18n.t("options.windowMode." .. mode) end,
            "windowMode")

        self.vsyncToggle = self:buildPendingToggle("vsync", "vsync",
            function(value) return value and 1 or 0 end)

        self.uncapFpsToggle = self:buildSettingToggle("uncapFps", FrameLimiter.setUncapped)

        self.showNebulaToggle = self:buildSettingToggle("showNebula",
            function(value) self:setNebulaVisible(value) end)

        self.applyButton = UI.Button.new{
            label = function() return I18n.t("options.applyGraphics") end,
            onSelect = function()
                UI.Sfx.press()
                self:applyPending()
            end,
        }
        self.applyButton.descKey = 'options.desc.apply'

        self.backButton = UI.Button.new{
            label = function() return I18n.t("options.back") end,
            onSelect = function() self:goBack() end,
        }
        self.backButton.descKey = 'options.desc.back'

        self:buildDialogs()

        self.tabs = {
            { name = "audio",     widgets = { self.volumeSlider, self.musicVolumeSlider,
                                               self.sfxVolumeSlider, } },
            { name = "interface", widgets = { self.languageSelector, self.themeSelector, self.themePreview,
                                               self.titleFontSelector, self.titleFontPreview,
                                               self.customCursorToggle, self.reducedMotionToggle,
                                               self.shareStatsToggle, } },
            { name = "graphics", widgets = { self.displaySelector, self.windowModeSelector, self.resolutionSelector,
                                               self.msaaSelector, self.showNebulaToggle, self.vsyncToggle, self.uncapFpsToggle } },
        }

        self.languageSelector.section = function() return I18n.t("options.section.appearance") end
        self.customCursorToggle.section = function() return I18n.t("options.section.accessibility") end
        self.shareStatsToggle.section = function() return I18n.t("options.section.privacy") end
        self.displaySelector.section = function() return I18n.t("options.section.display") end
        self.msaaSelector.section = function() return I18n.t("options.section.quality") end
        self.vsyncToggle.section = function() return I18n.t("options.section.performance") end

        -- Inventory retains stable localization IDs and existing save callbacks.
        -- Decorative preview rows carry no descKey and aren't real settings.
        local deferred = { display = true, resolution = true, msaa = true, displayMode = true, vsync = true }
        self.settingInventory = {}
        for _, tab in ipairs(self.tabs) do
            for _, widget in ipairs(tab.widgets) do
                if widget.descKey then
                    local id = widget.descKey:match("options.desc.(.+)")
                    self.settingInventory[#self.settingInventory + 1] = {
                        id = id, category = tab.name, widget = widget, helpKey = widget.descKey,
                        save = deferred[id] and "apply" or "immediate",
                        dependency = id == "resolution" and "display/displayMode" or nil,
                    }
                end
            end
        end

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

    self.revertDialog:close()
    self.unappliedDialog:close()
    self.errorDialog:close()
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
    self.uncapFpsToggle.value = self.settings.uncapFps
    self.showNebulaToggle.value = self.settings.showNebula
    self.keyboardInput = false
    for _, tab in ipairs(self.tabs) do tab.scrollY = 0 end
    self.scroll:setScroll(0)
    self:resetPending()
    self:selectTab(self.tabBar.index)
end

--- End any drag before a modal takes input. Closing restores visible focus.
function Options:openDialog(dialog)
    self.scroll:setScroll(self.scroll.scrollY) -- freeze the backdrop where it is
    self.group:releaseCapture()
    self.scroll.dragOffset = nil
    dialog:openDialog()
end

function Options:afterDialog(dialog)
    if dialog and not self:activeDialog() then
        self.group:refresh()
        self:revealFocus()
    end
end

function Options:update(dt)
    if self.layoutLanguage ~= I18n.current then self:layout() end
    local dialog = self:activeDialog()
    if dialog then
        dialog:update(dt)
        self:afterDialog(dialog)
    else
        self.scroll:update(dt)
        self.group:update(dt)
    end
end

function Options:mousepressed(x, y, button)
    self.mouseX, self.mouseY, self.keyboardInput = x, y, false
    local dialog = self:activeDialog()
    if dialog then
        dialog:mousepressed(x, y, button)
        self:afterDialog(dialog)
        return
    end
    if self.group.capture then return end
    self.scroll:setScroll(self.scroll.scrollY) -- controls must stay put during a click/drag
    if self.scroll:mousepressed(x, y, button) then return end
    self.group:mousepressed(x, y, button)
end

function Options:mousereleased(x, y, button)
    local dialog = self:activeDialog()
    if dialog then
        dialog:mousereleased(x, y, button)
        self:afterDialog(dialog)
        return
    end
    if button == 1 then self.scroll.dragOffset = nil end
    self.group:mousereleased(x, y, button)
end

function Options:mousemoved(x, y)
    self.mouseX, self.mouseY, self.keyboardInput = x, y, false
    local dialog = self:activeDialog()
    if dialog then return dialog:mousemoved(x, y) end
    if self.scroll:mousemoved(x, y) then return end
    self.group:mousemoved(x, y)
end

function Options:wheelmoved(x, y)
    -- Dialogs have no scrollable content; consume wheel input while open.
    if self:activeDialog() or self.group.capture or self.scroll.dragOffset then return end
    if not self.scroll:contains(self.mouseX, self.mouseY) then return end
    self.keyboardInput = false
    self.scroll:setScroll(self.scroll.targetY - y * UI.Theme.px(48), true)
end

function Options:keypressed(key)
    self.keyboardInput = true
    local dialog = self:activeDialog()
    if dialog then
        dialog:keypressed(key)
        self:afterDialog(dialog)
        return
    end
    self.group:releaseCapture()
    self.scroll.dragOffset = nil
    if key == "escape" then return self:goBack() end
    if key == "pageup" or key == "pagedown" then
        local current = self.group:focused()
        if not self.scroll.offsets[current] then return end
        local direction = key == "pageup" and -1 or 1
        self.scroll:setScroll(self.scroll.targetY + direction * self.scroll.h * 0.8, true)
        local best, distance
        local edge = direction < 0 and self.scroll.y or self.scroll.y + self.scroll.h
        for i, widget in ipairs(self.group.widgets) do
            local row = self.scroll.offsets[widget]
            local y = row and self.scroll.y + row.y - self.scroll.targetY
            if row and widget:isInteractive()
                and y >= self.scroll.y and y + widget.h <= self.scroll.y + self.scroll.h then
                local d = math.abs((direction < 0 and y or y + widget.h) - edge)
                if not distance or d < distance then best, distance = i, d end
            end
        end
        if best then self.group:setFocus(best) end
        self:revealFocus(true)
        return
    end
    local consumed = self.group:keypressed(key)
    self:revealFocus(true)
    return consumed
end

function Options:draw()
    local panel = self.panel
    UI.Label.draw{ text = I18n.t("options.title"), y = self.headingY, font = UI.Theme.font("heading") }
    self.tabBar:draw()
    UI.Theme.panel(panel.x, panel.y, panel.w, panel.h)
    self.scroll:draw()
    for _, button in ipairs(self:footerButtons()) do button:draw() end

    local function note(rect, text, color)
        UI.Label.draw{ text = text, x = rect.x, y = rect.y, width = rect.w,
            font = UI.Theme.font("small"), color = color or UI.Theme.colors.textMuted }
    end
    if self:isDirty() then note(self.statusRect, I18n.t("options.pendingGraphics"), UI.Theme.colors.warning) end
    note(self.hintRect, I18n.t("options.hint.navigation"), UI.Theme.colors.textDim)

    local dialog = self:activeDialog()
    if dialog then dialog:draw() end
    local overWidget, dangerous
    if dialog then overWidget, dangerous = dialog:hovering(self.mouseX, self.mouseY)
    else
        overWidget, dangerous = self.group:hovering(self.mouseX, self.mouseY)
        overWidget = overWidget or self.scroll:overBar(self.mouseX, self.mouseY)
    end
    UI.Cursor.setHover(overWidget, dangerous)
end

return Options
