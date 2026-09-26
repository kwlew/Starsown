--- Settings screen. This file is the shell -- tab bar, footer, layout, input
-- and dialog routing -- and each tab is its own module under states/options/:
--   audio.lua     - volume sliders
--   interface.lua - language/theme/fonts/cursor/motion/stats sharing
--   graphics.lua  - display/mode/resolution/MSAA/vsync, gated behind Apply
-- A tab is { name, widgets, sync(settings) }; adding one is a new module plus
-- an entry in `self.tabs` below. Shared row builders are in rows.lua.
--
-- Esc or "Back" returns to whichever state opened this one:
--   StateManager.fadeTo("options", { returnTo = "game" })
--
-- Abandoning a run isn't offered here: during a run this screen is reached
-- through the pause menu, and that's where quitting lives.

local StateManager = require "core.stateManager"
local Assets = require "core.assets"
local Settings = require "core.settings"
local UI = require "ui"
local I18n = require "core.i18n"
local Presence = require "services.presence"
local ScrollArea = require "ui.widgets.scrollArea"
local AudioTab = require "states.options.audio"
local InterfaceTab = require "states.options.interface"
local GraphicsTab = require "states.options.graphics"

local PANEL_PAD = 10
local PANEL_MAX_W = 720

local Options = {}

--- both layout and the focus list read this, so a footer button can never be
-- visible-but-unfocusable or vice versa
---@return table[]
function Options:footerButtons()
    return { self.backButton, self.graphics.applyButton }
end

--- Back/Esc: Graphics edits only take effect on Apply, so leaving with some
-- outstanding asks first
function Options:goBack()
    UI.Sfx.select()
    if self.graphics:isDirty() then return self.graphics:confirmLeave() end
    self:leave()
end

--- fades back to whichever screen opened this one
function Options:leave()
    StateManager.fadeTo(self.returnTo)
end

---@return table|nil # the open dialog, if any
function Options:activeDialog()
    for _, dialog in ipairs(self.graphics.dialogs) do
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
    local segmentW = (panelW - theme.px(6) * 2) / #self.tabs
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
    for _, dialog in ipairs(self.graphics.dialogs) do dialog:layout() end
end

function Options:resize()
    self.graphics:resize()
    self:layout()
    if self.keyboardInput then self:revealFocus() end
end

function Options:revealFocus(smooth)
    self.scroll:reveal(self.group:focused(), smooth)
end

--- StateManager calls enter(previousName, ...); opts.returnTo wins, else
-- wherever we came from. Guard stops Options targeting itself if re-entered.
function Options:enter(previousName, opts)
    Presence.show("options")
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

    if not self.tabs then
        self.graphics = GraphicsTab.new(self)
        self.tabs = { AudioTab.new(self), InterfaceTab.new(self), self.graphics }

        self.backButton = UI.Button.new{
            label = function() return I18n.t("options.back") end,
            onSelect = function() self:goBack() end,
        }
        self.backButton.descKey = "options.desc.back"

        local labels = {}
        for i, tab in ipairs(self.tabs) do
            labels[i] = function() return I18n.t("options.tab." .. tab.name) end
        end
        self.tabBar = UI.TabBar.new{
            tabs = labels,
            onChange = function(_, index)
                UI.Sfx.select()
                self:selectTab(index)
            end,
        }
    end

    self.keyboardInput = false
    for _, tab in ipairs(self.tabs) do
        tab:sync(self.settings)
        tab.scrollY = 0
    end
    self.scroll:setScroll(0)
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

--- PageUp/PageDown scroll a page and land focus on the nearest fully visible
-- row at that edge
---@param direction integer # -1 up, 1 down
function Options:pageFocus(direction)
    if not self.scroll.offsets[self.group:focused()] then return end
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
    if key == "pageup" or key == "pagedown" then return self:pageFocus(key == "pageup" and -1 or 1) end
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
    if self.graphics:isDirty() then note(self.statusRect, I18n.t("options.pendingGraphics"), UI.Theme.colors.warning) end
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
