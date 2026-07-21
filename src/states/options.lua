-- src/states/options.lua
-- Settings screen with two tabs:
--   General  — volume slider; applies live and persists immediately.
--   Graphics — resolution / display mode / vsync; changes accumulate in a
--              `pending` table and only take effect (and persist) when the
--              Apply button is pressed. Leaving the screen discards pending.
-- Esc or "Back" returns to the main menu.

local StateManager = require "lib.stateManager"
local Assets = require "lib.assets"
local Settings = require "lib.settings"
local UI = require "lib.ui"
local I18n = require "lib.i18n"

local HEADING_Y_RATIO = 0.12
local PANEL_Y_RATIO   = 0.32
local PANEL_PAD       = 20

local RESOLUTIONS = { {1280, 720}, {1600, 900}, {1920, 1080} }

-- Window modes in selector order. Display names come from the active locale
-- (options.windowMode.<mode>): "Borderless" is desktop-type fullscreen,
-- "Fullscreen" is exclusive.
local WINDOW_MODES = { "windowed", "borderless", "exclusive" }

local Options = {}

-- Index of a language code within the available-locales list (1 if not found),
-- used to sync the Language selector's display to the saved setting.
local function languageIndexFor(code)
    for i, entry in ipairs(I18n.available()) do
        if entry.code == code then return i end
    end
    return 1
end

-- Index into RESOLUTIONS matching the saved settings (1 if not found).
local function resolutionIndexFor(settings)
    for i, res in ipairs(RESOLUTIONS) do
        if res[1] == settings.res_x and res[2] == settings.res_y then
            return i
        end
    end
    return 1
end

local function windowModeIndexFor(mode)
    for i, name in ipairs(WINDOW_MODES) do
        if name == mode then return i end
    end
    return 1
end

function Options:setFocus(index)
    self.focusIndex = index
    for i, widget in ipairs(self.widgets) do
        widget.focused = (i == index)
    end
end

-- Moves focus, skipping disabled widgets (e.g. resolution while borderless).
function Options:moveFocus(delta)
    local count = #self.widgets
    local index = self.focusIndex
    repeat
        index = (index - 1 + delta) % count + 1
    until self.widgets[index].enabled ~= false or index == self.focusIndex
    self:setFocus(index)
end

-- Greys out rows that don't apply to the staged display mode: in borderless,
-- the game always runs at desktop resolution, so the resolution row is inert.
function Options:syncEnabledStates()
    self.resolutionSelector.enabled = self.pending.windowMode ~= "borderless"
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

-- Commits pending graphics changes: settings <- pending, apply, persist.
function Options:applyPending()
    if not self:isDirty() then return end

    local res = RESOLUTIONS[self.pending.resIndex]
    self.settings.res_x, self.settings.res_y = res[1], res[2]
    self.settings.windowMode = self.pending.windowMode
    self.settings.vsync = self.pending.vsync

    Settings.applyGraphics(self.settings)
    Settings.save(self.settings)
end

-- Rebuilds the focus list for the active tab: tab bar first, then the tab's
-- widgets, then the shared Back button.
function Options:selectTab(index)
    self.activeTab = index
    -- Keep the bar display in sync when switched programmatically (a direct
    -- field set never fires onChange, so no recursion).
    self.tabBar.index = index

    self.widgets = { self.tabBar }
    for _, widget in ipairs(self.tabs[index].widgets) do
        self.widgets[#self.widgets + 1] = widget
    end
    self.widgets[#self.widgets + 1] = self.backButton

    self:setFocus(1)
end

function Options:enter()
    -- Shared settings table, loaded and applied at boot by the loading state.
    self.settings = Assets.get("settings") or Settings.load()

    local function persist()
        Settings.save(self.settings)
    end

    if not self.tabs then
        -- Labels are functions (or format-time lookups) so they re-read the
        -- active language every draw — changing language updates the screen
        -- live, no rebuild.

        -- General tab: applies live, persists immediately.
        self.volumeSlider = UI.Slider.new{
            label = function() return I18n.t("options.volume") end,
            value = self.settings.volume,
            step = 0.1,
            onChange = function(value) -- live, fires throughout a drag
                self.settings.volume = value
                love.audio.setVolume(value)
            end,
            onRelease = function() -- final, fires when the change settles
                persist()
            end,
        }

        -- Language also applies live and persists immediately (General-tab
        -- behavior, like Volume). Options are the {code, name} locale entries.
        self.languageSelector = UI.Selector.new{
            label = function() return I18n.t("options.language") end,
            options = I18n.available(),
            format = function(entry) return entry.name end,
            onChange = function(entry)
                self.settings.language = entry.code
                I18n.setLanguage(entry.code)
                persist()
            end,
        }

        -- Graphics tab: writes to pending only; Apply commits.
        self.resolutionSelector = UI.Selector.new{
            label = function() return I18n.t("options.resolution") end,
            options = RESOLUTIONS,
            format = function(o) return o[1] .. "x" .. o[2] end,
            onChange = function(_, index)
                self.pending.resIndex = index
            end,
        }

        self.windowModeSelector = UI.Selector.new{
            label = function() return I18n.t("options.displayMode") end,
            options = WINDOW_MODES,
            format = function(mode) return I18n.t("options.windowMode." .. mode) end,
            onChange = function(mode)
                self.pending.windowMode = mode
                self:syncEnabledStates()
            end,
        }

        self.vsyncToggle = UI.Toggle.new{
            label = function() return I18n.t("options.vsync") end,
            onChange = function(value)
                self.pending.vsync = value and 1 or 0
            end,
        }

        self.applyButton = UI.Button.new{
            label = function()
                return self:isDirty() and I18n.t("options.applyDirty") or I18n.t("options.apply")
            end,
            onSelect = function()
                self:applyPending()
            end,
        }

        self.backButton = UI.Button.new{
            label = function() return I18n.t("options.back") end,
            onSelect = function()
                StateManager.switch("mainMenu")
            end,
        }

        self.tabs = {
            { name = "general",  widgets = { self.volumeSlider, self.languageSelector } },
            { name = "graphics", widgets = { self.resolutionSelector, self.windowModeSelector,
                                             self.vsyncToggle, self.applyButton } },
        }

        self.tabBar = UI.TabBar.new{
            tabs = {
                function() return I18n.t("options.tab.general") end,
                function() return I18n.t("options.tab.graphics") end,
            },
            onChange = function(_, index)
                self:selectTab(index)
            end,
        }
    end

    -- Fresh visit: discard any stale pending edits, re-sync live values.
    self.volumeSlider.value = self.settings.volume
    self.languageSelector.index = languageIndexFor(self.settings.language)
    self:resetPending()
    self:selectTab(self.tabBar.index)
end

function Options:update(dt)
    for _, widget in ipairs(self.widgets) do
        widget:update(dt)
    end
end

function Options:keypressed(key)
    if key == "escape" then
        StateManager.switch("mainMenu")
        return
    end

    local widget = self.widgets[self.focusIndex]
    if key == "up" or key == "w" then
        self:moveFocus(-1)
    elseif key == "down" or key == "s" then
        self:moveFocus(1)
    elseif key == "left" or key == "a" then
        if widget.adjust then widget:adjust(-1) end
    elseif key == "right" or key == "d" then
        if widget.adjust then widget:adjust(1) end
    elseif key == "return" or key == "kpenter" or key == "space" then
        if widget.activate then widget:activate() end
    end
end

function Options:mousemoved(x, y)
    -- A drag in progress owns the mouse; don't steal focus mid-drag.
    self.volumeSlider:mousemoved(x, y)
    if self.volumeSlider.dragging then return end

    -- Let widgets with hover feedback (chevrons, tab segments) track the cursor.
    for _, widget in ipairs(self.widgets) do
        if widget.mousemoved and widget ~= self.volumeSlider then
            widget:mousemoved(x, y)
        end
    end

    for i, widget in ipairs(self.widgets) do
        if widget.enabled ~= false and widget:contains(x, y) then
            self:setFocus(i)
            return
        end
    end
end

function Options:mousepressed(x, y, button)
    for i, widget in ipairs(self.widgets) do
        if widget.enabled ~= false and widget:contains(x, y) then
            self:setFocus(i)
            widget:mousepressed(x, y, button)
            return
        end
    end
end

function Options:mousereleased(x, y, button)
    self.volumeSlider:mousereleased(x, y, button)
end

function Options:draw()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local m = UI.Theme.metrics

    UI.Label.draw{
        text = I18n.t("options.title"),
        y = h * HEADING_Y_RATIO,
        font = UI.Theme.font("heading"),
    }

    -- Panel sized to the active tab's rows, centered horizontally, with the
    -- tab bar sitting just above it and Back below it.
    local rows = #self.tabs[self.activeTab].widgets
    local panelW = math.min(560, w * 0.72)
    local panelH = PANEL_PAD * 2 + rows * m.rowHeight + (rows - 1) * m.rowGap
    local panelX = (w - panelW) / 2
    local panelY = h * PANEL_Y_RATIO

    self.tabBar.x = panelX
    self.tabBar.y = panelY - m.rowHeight - m.rowGap
    self.tabBar.w = panelW
    self.tabBar:draw()

    UI.Theme.panel(panelX, panelY, panelW, panelH)

    for i, widget in ipairs(self.tabs[self.activeTab].widgets) do
        widget.x = panelX + PANEL_PAD
        widget.y = panelY + PANEL_PAD + (i - 1) * (m.rowHeight + m.rowGap)
        widget.w = panelW - PANEL_PAD * 2
        widget:draw()
    end

    self.backButton.x = panelX
    self.backButton.y = panelY + panelH + m.rowGap
    self.backButton.w = panelW
    self.backButton:draw()

    local hint = I18n.t(self.activeTab == 2 and "options.hint.graphics" or "options.hint.general")
    UI.Label.draw{
        text = hint,
        y = h - 48,
        font = UI.Theme.font("small"),
        color = UI.Theme.colors.textDim,
    }
end

return Options
