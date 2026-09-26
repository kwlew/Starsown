--- Options > Graphics. Display, mode, resolution, MSAA and vsync edits
-- accumulate in `pending` and only take effect (and persist) on Apply, which
-- then opens a countdown that auto-reverts unless confirmed -- an unreadable
-- mode can leave the player unable to click anything. Leaving with pending
-- edits asks first. The purely cosmetic rows (nebula, uncapped fps) can't
-- strand anyone, so they apply immediately like every other tab.

local Assets = require "core.assets"
local Settings = require "core.settings"
local FrameLimiter = require "core.frameLimiter"
local DisplayLimits = require "core.displayLimits"
local UI = require "ui"
local I18n = require "core.i18n"
local Rows = require "states.options.rows"

local REVERT_SECONDS = 10

local WINDOWED_FLOOR = { 1280, 720 } -- the one size always on offer if a desktop-size query ever fails

--- common display resolutions offered for windowed mode, rather than
-- fractions of the desktop -- these are sizes players actually expect to
-- pick from. windowedResolutions filters this to what fits the selected
-- display and adds that display's own native size, so a panel whose size
-- isn't one of these standard ones can still be selected (e.g. maximized).
local WINDOWED_RESOLUTIONS = {
    { 800, 600 }, { 1024, 768 }, { 1152, 864 }, { 1280, 720 }, { 1280, 800 },
    { 1280, 960 }, { 1280, 1024 }, { 1360, 768 }, { 1366, 768 }, { 1440, 900 },
    { 1536, 864 }, { 1600, 900 }, { 1600, 1200 }, { 1680, 1050 }, { 1920, 1080 },
    { 1920, 1200 }, { 2560, 1080 }, { 2560, 1440 }, { 2560, 1600 }, { 3440, 1440 },
    { 3840, 2160 },
}

local MSAA = Settings.MSAA_LEVELS -- owned by Settings; conf.lua validates against the same list at boot

local WINDOW_MODES = { "windowed", "borderless", "exclusive" }

---@return integer[] # 1..love.window.getDisplayCount(); LÖVE exposes no monitor names to label these with
local function displayOptions()
    local options = {}
    for i = 1, love.window.getDisplayCount() do options[i] = i end
    return options
end

--- exclusive fullscreen offers exactly the modes the display reports
-- (de-duplicated by size, smallest first -- so Right steps up in size, same
-- as every other numeric selector, e.g. MSAA) -- getFullscreenModes is
-- specifically about fullscreen capability, so it's never used for the
-- windowed case below, which asks a different question entirely.
---@param display integer
---@return table[] # { {w, h}, ... }
local function exclusiveResolutions(display)
    local modes = love.window.getFullscreenModes(display)
    table.sort(modes, function(a, b)
        if a.width ~= b.width then return a.width < b.width end
        return a.height < b.height
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

--- windowed sizing offers WINDOWED_RESOLUTIONS filtered to what fits the
-- display's own desktop size -- a windowed size larger than the desktop
-- makes no more sense than a fullscreen mode the display doesn't support --
-- plus that desktop size itself, so a panel whose native size isn't one of
-- the standard entries can still be picked (maximized). A monitor smaller
-- than every standard entry falls through to just its own desktop size
-- here, or WINDOWED_FLOOR via resolutionsFor if even that query fails.
---@param display integer
---@return table[] # { {w, h}, ... }, smallest first -- so Right steps up in size
local function windowedResolutions(display)
    local deskW, deskH = love.window.getDesktopDimensions(display)
    if type(deskW) ~= "number" or deskW <= 0 or deskH <= 0 then return {} end

    local minW, minH = DisplayLimits.minimum(display)
    local seen, list = {}, {}
    local function add(w, h)
        local key = w .. "x" .. h
        if not seen[key] and w >= minW and h >= minH and w <= deskW and h <= deskH then
            seen[key] = true
            list[#list + 1] = { w, h }
        end
    end
    for _, res in ipairs(WINDOWED_RESOLUTIONS) do add(res[1], res[2]) end
    add(deskW, deskH)

    table.sort(list, function(a, b)
        if a[1] ~= b[1] then return a[1] < b[1] end
        return a[2] < b[2]
    end)
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

--- inserts w,h keeping `options` sorted the same way windowedResolutions/
-- exclusiveResolutions do (smallest first), and returns where it landed
---@param options table[]
---@param w number
---@param h number
---@return integer
local function insertSorted(options, w, h)
    local index = #options + 1
    for i, option in ipairs(options) do
        if w < option[1] or (w == option[1] and h < option[2]) then index = i; break end
    end
    table.insert(options, index, { w, h })
    return index
end

local GraphicsTab = {}
GraphicsTab.__index = GraphicsTab

--- writes into `pending` only and syncs derived enabled-states; Apply is what
-- commits. `pendingKey` isn't always `key` (the displayMode row's field is
-- `windowMode`). `valueOf(option, index)` picks what's stored -- the option
-- itself by default, but the resolution row stores the index: its list is
-- rebuilt live as display/mode change, so only an index stays meaningful.
---@param key string # i18n label and description key
---@param options any[]
---@param format fun(option: any): string
---@param pendingKey string
---@param valueOf? fun(option: any, index: integer): any
---@return table
function GraphicsTab:pendingSelector(key, options, format, pendingKey, valueOf)
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

---@param key string # i18n label and description key
---@param pendingKey string
---@param transform fun(value: boolean): any # the widget's boolean -> what `pending` stores
---@return table
function GraphicsTab:pendingToggle(key, pendingKey, transform)
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

-- setMode recreates the GL context, which wipes the nebula's baked canvases.
local function applyGraphics(settings)
    local ok, err, adjusted = Settings.applyGraphics(settings)
    local nebula = Assets.get("nebula")
    if nebula and nebula:isBaked() then nebula:bake() end
    return ok, err, adjusted
end

--- A disabled-at-boot nebula is intentionally not baked during loading. Pay
-- that one-time cost only if the player later asks to see it.
---@param value boolean
local function setNebulaVisible(value)
    local nebula = Assets.get("nebula")
    if not nebula then return end
    if value and not nebula:isBaked() then nebula:bake() end
    nebula.enabled = value
end

local function setStarsVisible(value)
    local stars = Assets.get("stars")
    if not stars then return end
    stars.enabled = value
end

---@param screen table # the Options state
---@return table
function GraphicsTab.new(screen)
    local self = setmetatable({ name = "graphics", screen = screen }, GraphicsTab)
    local settings = screen.settings

    -- A read-only row's reason has to live in the value text itself, not
    -- the shared description below: keyboard/mouse focus both skip
    -- non-interactive widgets, so a row that can never be focused can
    -- never surface an explanation that depends on being focused first.
    self.displaySelector = self:pendingSelector("display", displayOptions(),
        function(n)
            local text = I18n.t("options.displayOption", { n = n })
            if self.displaySelector and self.displaySelector.readOnly then
                text = text .. " · " .. I18n.t("options.note.monitor")
            end
            return text
        end,
        "display")

    self.resolutionSelector = self:pendingSelector("resolution",
        resolutionsFor(settings.display, settings.windowMode),
        function(o)
            local text = o[1] .. "x" .. o[2]
            if self.resolutionSelector and self.resolutionSelector.readOnly then
                text = text .. " · " .. I18n.t("options.note.borderless")
            end
            return text
        end,
        "resIndex", function(_, index) return index end)

    self.msaaSelector = self:pendingSelector("msaa", MSAA,
        function(samples)
            if samples == 0 then return I18n.t("options.msaaOff") end
            return samples .. "x"
        end,
        "msaa")

    self.windowModeSelector = self:pendingSelector("displayMode", WINDOW_MODES,
        function(mode) return I18n.t("options.windowMode." .. mode) end,
        "windowMode")

    self.vsyncToggle = self:pendingToggle("vsync", "vsync", function(value) return value and 1 or 0 end)
    self.uncapFpsToggle = Rows.settingToggle(screen, "uncapFps", FrameLimiter.setUncapped)
    self.showNebulaToggle = Rows.settingToggle(screen, "showNebula", setNebulaVisible)
    self.showStarsToggle = Rows.settingToggle(screen, "showStars", setStarsVisible)

    self.displaySelector.section = function() return I18n.t("options.section.display") end
    self.msaaSelector.section = function() return I18n.t("options.section.quality") end
    self.vsyncToggle.section = function() return I18n.t("options.section.performance") end

    self.widgets = { self.displaySelector, self.windowModeSelector, self.resolutionSelector,
        self.msaaSelector, self.showNebulaToggle, self.showStarsToggle, self.vsyncToggle, self.uncapFpsToggle }

    self.applyButton = UI.Button.new{
        label = function() return I18n.t("options.applyGraphics") end,
        icon = "apply",
        onSelect = function()
            UI.Sfx.press()
            self:applyPending()
        end,
    }
    self.applyButton.descKey = "options.desc.apply"

    self:buildDialogs()
    return self
end

--- the three prompts this tab owns: the countdown that auto-reverts an
-- applied change, the one that catches leaving with edits outstanding, and
-- the error report when a mode fails to apply
function GraphicsTab:buildDialogs()
    local screen = self.screen

    self.revertDialog = UI.Dialog.new{
        title = function() return I18n.t("dialog.revert.title") end,
        fontRole = "help",
        message = function(dialog)
            local text = I18n.t("dialog.revert.message", { n = math.max(0, math.ceil(dialog.remaining or 0)) })
            if self.previewAdjusted then
                local v = screen.settings
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
        onTimeout = function() self:revert() end,
        onCancel = function() self:revert() end,
        buttons = {
            { label = function() return I18n.t("dialog.revert.revert") end, danger = true,
              onSelect = function() self:revert() end },
            { label = function() return I18n.t("dialog.revert.keep") end,
              onSelect = function() self:keep() end },
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
                  screen:leave()
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
        message = function() return I18n.t("options.error." .. (self.error or "failed")) end,
        fontRole = "help",
        buttons = { { label = function() return I18n.t("dialog.close") end,
            onSelect = function() self.errorDialog:close() end } },
    }

    self.dialogs = { self.revertDialog, self.unappliedDialog, self.errorDialog }
    for _, dialog in ipairs(self.dialogs) do dialog:setFocusSound(UI.Sfx.focus) end
end

--- closes anything left open and resets pending to the saved settings; called
-- on each visit
---@param settings table
function GraphicsTab:sync(settings)
    for _, dialog in ipairs(self.dialogs) do dialog:close() end
    self.revertTo = nil
    self.leaveAfterApply = false
    self.uncapFpsToggle.value = settings.uncapFps
    self.showNebulaToggle.value = settings.showNebula
    self.showStarsToggle.value = settings.showStars
    self:resetPending()
end

--- Only windowed modes may preserve custom sizes. A monitor/mode change
-- must not insert a resolution unsupported by the newly selected display.
function GraphicsTab:rebuildResolutions(targetW, targetH)
    local settings = self.screen.settings
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
        local isLive = display == settings.display and mode == settings.windowMode
            and targetW == settings.res_x and targetH == settings.res_y
        if (w == targetW and h == targetH) or isLive then
            index = insertSorted(options, targetW, targetH)
        end
    end
    if not index and mode == "exclusive" and display == settings.display
        and mode == settings.windowMode and targetW == settings.res_x and targetH == settings.res_y then
        index = insertSorted(options, targetW, targetH) -- the currently active mode is known to work
    end
    self.resolutionSelector.options = options
    -- no match at all: default to the largest (last, now that Right steps up in size) available size
    self.pending.resIndex = index or #options
    self.resolutionSelector.index = self.pending.resIndex
end

--- keeps derived enabled-states in sync with pending; call after any mutation
-- of `pending`. Resolution row is inert in borderless (always desktop res
-- there); Apply greys out when there's nothing to apply. Also re-derives the
-- resolution list, since a display or mode change (either lands here too)
-- can change which one applies.
function GraphicsTab:syncEnabledStates()
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
    self.screen.group:refresh() -- move focus off a row that just went inert
    if self.screen.activeTab then self.screen:layout() end
end

---@return boolean # whether there are edits waiting on Apply
function GraphicsTab:isDirty()
    local settings = self.screen.settings
    local selected = self.resolutionSelector.options[self.pending.resIndex]
    return not selected
        or (self.pending.windowMode ~= "borderless"
            and (selected[1] ~= settings.res_x or selected[2] ~= settings.res_y))
        or self.pending.msaa ~= settings.msaa
        or self.pending.windowMode ~= settings.windowMode
        or self.pending.vsync ~= settings.vsync
        or self.pending.display ~= settings.display
end

--- resets pending graphics changes to the live settings and syncs widget
-- displays (setting fields directly never fires onChange)
function GraphicsTab:resetPending()
    local settings = self.screen.settings
    self.resolutionMode = nil
    self.displaySelector.options = displayOptions()
    local msaaIndex = Rows.indexWhere(MSAA, function(s) return s == settings.msaa end)
    self.pending = {
        display = settings.display,
        msaa = MSAA[msaaIndex], -- the sample count itself, not an index, unlike resIndex (a resolution is a pair)
        windowMode = settings.windowMode,
        vsync = settings.vsync,
    }
    self.displaySelector.index = Rows.indexWhere(self.displaySelector.options,
        function(n) return n == self.pending.display end)
    self.msaaSelector.index = msaaIndex
    self.windowModeSelector.index = Rows.indexWhere(WINDOW_MODES, function(m) return m == self.pending.windowMode end)
    self.vsyncToggle.value = self.pending.vsync == 1
    self.baselineWidth, self.baselineHeight = settings.res_x, settings.res_y

    self:rebuildResolutions(settings.res_x, settings.res_y)
    self:syncEnabledStates()
end

--- A user window drag updates live settings before the resize callback.
-- Preserve an explicit pending resolution edit, but let an untouched one
-- follow the new window size without creating a false Apply state.
function GraphicsTab:resize()
    local settings = self.screen.settings
    if self.pending and settings.windowMode == "windowed" and not self.revertTo then
        local selected = self.resolutionSelector:selected()
        if selected and selected[1] == self.baselineWidth and selected[2] == self.baselineHeight then
            self:rebuildResolutions(settings.res_x, settings.res_y)
            self.applyButton.enabled = self:isDirty()
            self.screen.group:refresh()
        end
    end
    self.baselineWidth, self.baselineHeight = settings.res_x, settings.res_y
end

--- Back/Esc with edits outstanding: the greyed-out Apply button isn't much
-- of a reminder, so ask whether to apply or discard them
function GraphicsTab:confirmLeave()
    self.screen:openDialog(self.unappliedDialog)
end

function GraphicsTab:showError(key)
    self.error = key
    self.screen:openDialog(self.errorDialog)
end

function GraphicsTab:applyPending()
    if not self:isDirty() then return end
    local settings = self.screen.settings
    local ready = Settings.beginGraphicsPreview(settings)
    if not ready then return self:showError("saveFailed") end
    self.revertTo = Settings.graphicsSnapshot(settings)
    local res = self.resolutionSelector.options[self.pending.resIndex]
    settings.res_x, settings.res_y = res[1], res[2]
    settings.msaa, settings.windowMode = self.pending.msaa, self.pending.windowMode
    settings.vsync, settings.display = self.pending.vsync, self.pending.display
    local ok, _, adjusted = applyGraphics(settings)
    if not ok then
        local recovery = self:restore()
        return self:showError(recovery or "failed")
    end
    self.previewAdjusted = adjusted
    self:resetPending()
    self.screen:openDialog(self.revertDialog)
end

function GraphicsTab:keep()
    local ok = Settings.endGraphicsPreview(self.screen.settings, true)
    if not ok then
        self.revertDialog:close()
        local recovery = self:restore()
        return self:showError(recovery or "saveFailed")
    end
    self.revertDialog:close()
    self.revertTo, self.previewAdjusted = nil, nil
    self:resetPending()
    if self.leaveAfterApply then self.leaveAfterApply = false; self.screen:leave() end
end

-- If the old monitor disappeared, try a conservative window on the primary
-- display. Never replace the last confirmed file with an unconfirmed fallback.
function GraphicsTab:restore()
    self.leaveAfterApply = false
    local baseline = self.revertTo
    if not baseline then return end
    local settings = self.screen.settings
    for key, value in pairs(baseline) do settings[key] = value end
    local ok = applyGraphics(settings)
    local recovery
    if not ok then
        settings.display, settings.windowMode = 1, "windowed"
        settings.res_x, settings.res_y = DisplayLimits.minimum(1)
        settings.msaa, settings.vsync = 0, 1
        ok = applyGraphics(settings)
        recovery = ok and "recovery" or "restoreFailed"
    end
    if not ok then Settings.readGraphics(settings) end
    Settings.endGraphicsPreview(settings, false)
    self.revertTo, self.previewAdjusted = nil, nil
    self:resetPending()
    return recovery
end

function GraphicsTab:revert()
    self.revertDialog:close()
    local recovery = self:restore()
    if recovery then self:showError(recovery) end
end

return GraphicsTab
