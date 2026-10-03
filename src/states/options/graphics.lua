--- Options > Graphics. Mode/size/MSAA/vsync/display edits wait in
-- `pending` until Apply, then auto-revert unless kept.

local Backdrop = require("states.shared.backdrop")
local Dialogs = require("states.options.graphics.dialogs")
local FrameLimiter = require("core.frameLimiter")
local I18n = require("core.i18n")
local Limits = require("core.display.limits")
local Resolutions = require("states.options.graphics.resolutions")
local Rows = require("states.options.rows")
local Settings = require("core.settings")
local UI = require("ui")

local GraphicsTab = {}
GraphicsTab.__index = GraphicsTab

local MSAA = Settings.MSAA_LEVELS
local WINDOW_MODES = Settings.WINDOW_MODES

--- setMode wipes GL canvases, so the nebula rebakes
---@param settings table
---@return boolean ok
---@return string|nil err
---@return boolean|nil adjusted
local function applyToWindow(settings)
    local ok, err, adjusted, changed = Settings.applyGraphics(settings)
    if changed then Backdrop.rebake() end
    return ok, err, adjusted
end

--- a read-only row explains itself in its value text
---@param selector table
---@param text string
---@param noteKey string
---@return string
local function withNote(selector, text, noteKey)
    if selector and selector.readOnly then return text .. " · " .. I18n.t(noteKey) end
    return text
end

---@param key string # i18n label
---@param options any[]
---@param format fun(option: any): string
---@param store fun(option: any, index: integer)
---@return table
function GraphicsTab:pendingSelector(key, options, format, store)
    return UI.Selector.new{
        label = function() return I18n.t("options." .. key) end,
        options = options,
        format = format,
        onChange = function(option, index)
            UI.Sfx.select()
            store(option, index)
            self:syncEnabledStates()
        end,
    }
end

function GraphicsTab:buildPendingRows()
    self.display = self:pendingSelector("display", Resolutions.displays(), function(n)
        return withNote(self.display, I18n.t("options.displayOption", { n = n }), "options.note.monitor")
    end, function(n) self.pending.display = n end)

    self.windowMode = self:pendingSelector("displayMode", WINDOW_MODES, function(mode)
        return I18n.t("options.windowMode." .. mode)
    end, function(mode) self.pending.windowMode = mode end)

    -- stores the index: the list changes with display and mode
    self.resolution = self:pendingSelector("resolution", {}, function(size)
        return withNote(self.resolution, size[1] .. "x" .. size[2], "options.note.borderless")
    end, function(_, index) self.pending.resIndex = index end)

    self.msaa = self:pendingSelector("msaa", MSAA, function(samples)
        return samples == 0 and I18n.t("options.msaaOff") or samples .. "x"
    end, function(samples) self.pending.msaa = samples end)

    self.vsync = UI.Toggle.new{
        label = function() return I18n.t("options.vsync") end,
        onChange = function(value)
            UI.Sfx.select()
            self.pending.vsync = value and 1 or 0
            self:syncEnabledStates()
        end,
    }
end

---@param screen table # the Options state
---@return table
function GraphicsTab.new(screen)
    local self = setmetatable({ name = "graphics", screen = screen, pending = {} }, GraphicsTab)
    self:buildPendingRows()
    self.uncapFps = Rows.toggle(screen, "uncapFps", FrameLimiter.setUncapped)
    self.showNebula = Rows.toggle(screen, "showNebula", Backdrop.showNebula)
    self.showStars = Rows.toggle(screen, "showStars", Backdrop.showStars)

    self.display.section = Rows.section("display")
    self.msaa.section = Rows.section("quality")
    self.vsync.section = Rows.section("performance")

    self.widgets = { self.display, self.windowMode, self.resolution, self.msaa,
        self.showNebula, self.showStars, self.vsync, self.uncapFps }

    self.applyButton = UI.Button.new{
        label = function() return I18n.t("options.applyGraphics") end,
        icon = "apply",
        onSelect = function()
            UI.Sfx.press()
            self:applyPending()
        end,
    }

    self.dialogs = Dialogs.build(self)
    return self
end

---@param settings table
function GraphicsTab:sync(settings)
    for _, dialog in ipairs(self.dialogs.all) do dialog:close() end
    self.revertTo, self.leaveAfterApply = nil, false
    self.uncapFps.value = settings.uncapFps
    self.showNebula.value = settings.showNebula
    self.showStars.value = settings.showStars
    self:resetPending()
end

--- rebuilds the size list, selecting the target size when allowed
---@param targetW number|nil
---@param targetH number|nil
function GraphicsTab:rebuildResolutions(targetW, targetH)
    local settings, pending = self.screen.settings, self.pending
    local mode, display = pending.windowMode, pending.display
    local options = Resolutions.list(display, mode)
    local index = targetW and Resolutions.find(options, targetW, targetH)

    if not index and targetW and targetW > 0 and targetH > 0 then
        local isLive = display == settings.display and mode == settings.windowMode
            and targetW == settings.res_x and targetH == settings.res_y
        local fitW, fitH = Limits.windowSize(targetW, targetH, display)
        local fits = fitW == targetW and fitH == targetH
        -- keep custom windowed sizes, and whatever is running now
        if (mode == "windowed" and (fits or isLive)) or (mode == "exclusive" and isLive) then
            index = Resolutions.insert(options, targetW, targetH)
        end
    end

    self.resolution.options = options
    pending.resIndex = index or #options -- else the largest
    self.resolution.index = pending.resIndex
end

--- re-derives everything that depends on `pending`
function GraphicsTab:syncEnabledStates()
    local current = self.resolution:selected()
    local mode = self.pending.windowMode
    if mode == "borderless" and self.resolutionMode ~= "borderless" then
        self.windowedResolution = current -- remembered for leaving borderless
    elseif self.resolutionMode == "borderless" and mode ~= "borderless" then
        current = self.windowedResolution
    end
    self:rebuildResolutions(current and current[1], current and current[2])
    self.resolutionMode = mode

    self.resolution.readOnly = mode == "borderless"
    self.display.readOnly = #self.display.options == 1
    self.applyButton.enabled = self:isDirty()
    self.screen.group:refresh()
    if self.screen.activeTab then self.screen:layout() end
end

---@return boolean # edits are waiting on Apply
function GraphicsTab:isDirty()
    local settings, pending = self.screen.settings, self.pending
    local size = self.resolution.options[pending.resIndex]
    return not size
        or (pending.windowMode ~= "borderless" and (size[1] ~= settings.res_x or size[2] ~= settings.res_y))
        or pending.msaa ~= settings.msaa
        or pending.windowMode ~= settings.windowMode
        or pending.vsync ~= settings.vsync
        or pending.display ~= settings.display
end

--- points everything back at the live settings
function GraphicsTab:resetPending()
    local settings = self.screen.settings
    self.resolutionMode = nil
    self.display.options = Resolutions.displays()
    local msaaIndex = Rows.indexWhere(MSAA, function(s) return s == settings.msaa end)
    self.pending = {
        display = settings.display,
        msaa = MSAA[msaaIndex],
        windowMode = settings.windowMode,
        vsync = settings.vsync,
    }
    Rows.selectValue(self.display, settings.display)
    Rows.selectValue(self.windowMode, settings.windowMode)
    self.msaa.index = msaaIndex
    self.vsync.value = settings.vsync == 1
    self.baselineW, self.baselineH = settings.res_x, settings.res_y

    self:rebuildResolutions(settings.res_x, settings.res_y)
    self:syncEnabledStates()
end

--- an untouched size row follows a window drag
function GraphicsTab:resize()
    local settings = self.screen.settings
    if settings.windowMode == "windowed" and not self.revertTo then
        local size = self.resolution:selected()
        if size and size[1] == self.baselineW and size[2] == self.baselineH then
            self:rebuildResolutions(settings.res_x, settings.res_y)
            self.applyButton.enabled = self:isDirty()
            self.screen.group:refresh()
        end
    end
    self.baselineW, self.baselineH = settings.res_x, settings.res_y
end

function GraphicsTab:confirmLeave()
    self.screen:openDialog(self.dialogs.unapplied)
end

---@param key string # options.error.<key>
function GraphicsTab:showError(key)
    self.error = key
    self.screen:openDialog(self.dialogs.error)
end

function GraphicsTab:applyPending()
    if not self:isDirty() then return end
    local settings, pending = self.screen.settings, self.pending
    if not Settings.beginGraphicsPreview(settings) then return self:showError("saveFailed") end

    self.revertTo = Settings.graphicsSnapshot(settings)
    local size = self.resolution.options[pending.resIndex]
    settings.res_x, settings.res_y = size[1], size[2]
    settings.msaa, settings.windowMode = pending.msaa, pending.windowMode
    settings.vsync, settings.display = pending.vsync, pending.display

    local ok, _, adjusted = applyToWindow(settings)
    if not ok then return self:showError(self:restore() or "failed") end
    self.previewAdjusted = adjusted
    self:resetPending()
    self.screen:openDialog(self.dialogs.revert)
end

function GraphicsTab:keep()
    self.dialogs.revert:close()
    if not Settings.endGraphicsPreview(self.screen.settings, true) then
        return self:showError(self:restore() or "saveFailed")
    end
    self.revertTo, self.previewAdjusted = nil, nil
    self:resetPending()
    if self.leaveAfterApply then
        self.leaveAfterApply = false
        self.screen:leave()
    end
end

--- back to confirmed graphics, else a safe window
---@return string|nil recovery # error key, if not a clean restore
function GraphicsTab:restore()
    self.leaveAfterApply = false
    local baseline = self.revertTo
    if not baseline then return nil end
    local settings = self.screen.settings
    for key, value in pairs(baseline) do settings[key] = value end

    local recovery
    if not applyToWindow(settings) then
        settings.display, settings.windowMode = 1, "windowed"
        settings.res_x, settings.res_y = Limits.minimum(1)
        settings.msaa, settings.vsync = 0, 1
        local ok = applyToWindow(settings)
        recovery = ok and "recovery" or "restoreFailed"
        if not ok then Settings.readGraphics(settings) end
    end

    Settings.endGraphicsPreview(settings, false)
    self.revertTo, self.previewAdjusted = nil, nil
    self:resetPending()
    return recovery
end

function GraphicsTab:revert()
    self.dialogs.revert:close()
    local recovery = self:restore()
    if recovery then self:showError(recovery) end
end

function GraphicsTab:discardAndLeave()
    self:resetPending()
    self.screen:leave()
end

function GraphicsTab:applyAndLeave()
    self.leaveAfterApply = true
    self:applyPending()
end

return GraphicsTab
