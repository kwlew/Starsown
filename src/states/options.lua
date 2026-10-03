--- Settings screen shell: tabs, footer, scrolling rows, dialogs.
-- Each tab is { name, widgets, sync(settings) } in states/options/.

local Assets = require("core.assets")
local AudioTab = require("states.options.audio")
local BackButton = require("states.shared.backButton")
local GraphicsTab = require("states.options.graphics")
local I18n = require("core.i18n")
local InterfaceTab = require("states.options.interface")
local Layout = require("states.options.layout")
local Paging = require("states.options.paging")
local Pointer = require("states.shared.pointer")
local Presence = require("services.presence")
local Settings = require("core.settings")
local StateManager = require("core.state.manager")
local UI = require("ui")

local Options = {}

function Options:build()
    self.pointer = Pointer.new()
    self.scroll = UI.ScrollArea.new()
    self.group = UI.FocusGroup.new()
    self.group.onFocusChanged = UI.Sfx.focus
    self.group.pointerFilter = function(widget, x, y) return self.scroll:allowsPointer(widget, x, y) end

    self.graphics = GraphicsTab.new(self)
    self.tabs = { AudioTab.new(self), InterfaceTab.new(self), self.graphics }
    self.backButton = BackButton("options.back", function() self:goBack() end)

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

---@param previousName string|nil
---@param opts? table # { returnTo?: string }
function Options:enter(previousName, opts)
    Presence.show("options")
    self.returnTo = StateManager.returnTarget(previousName, opts, "options")
    self.settings = Assets.get("settings") or Settings.load()
    if not self.tabs then self:build() end

    self.pointer:reset()
    self.keyboardInput = false
    for _, tab in ipairs(self.tabs) do
        tab:sync(self.settings)
        tab.scrollY = 0
    end
    self.scroll:setScroll(0)
    self:selectTab(self.tabBar.index)
end

---@return table[]
function Options:footerButtons()
    return { self.backButton, self.graphics.applyButton }
end

---@return table[]
function Options:dialogs()
    return self.graphics.dialogs.all
end

---@return table|nil
function Options:activeDialog()
    for _, dialog in ipairs(self:dialogs()) do
        if dialog:isOpen() then return dialog end
    end
end

--- ends any drag in the rows or scrollbar
function Options:releaseDrags()
    self.group:releaseCapture()
    self.scroll:mousereleased(0, 0, 1)
end

---@param index integer
function Options:selectTab(index)
    if self.activeTab then self.tabs[self.activeTab].scrollY = self.scroll.targetY end
    self:releaseDrags()
    self.activeTab = index
    self.tabBar.index = index -- direct set; no onChange

    local widgets = { self.tabBar }
    for _, widget in ipairs(self.tabs[index].widgets) do widgets[#widgets + 1] = widget end
    for _, button in ipairs(self:footerButtons()) do widgets[#widgets + 1] = button end
    self.group:setWidgets(widgets)
    self:layout(self.tabs[index].scrollY or 0)
end

---@param scrollY? number
function Options:layout(scrollY)
    if not self.activeTab then return end
    Layout.apply(self, scrollY)
    self.layoutLanguage = I18n.current
end

function Options:resize()
    self.graphics:resize()
    self:layout()
    if self.keyboardInput then self:revealFocus() end
end

---@param smooth? boolean
function Options:revealFocus(smooth)
    self.scroll:reveal(self.group:focused(), smooth)
end

--- unapplied Graphics edits ask first
function Options:goBack()
    UI.Sfx.select()
    if self.graphics:isDirty() then return self.graphics:confirmLeave() end
    self:leave()
end

function Options:leave()
    StateManager.fadeTo(self.returnTo)
end

---@param dialog table
function Options:openDialog(dialog)
    self.scroll:setScroll(self.scroll.scrollY) -- freeze the rows
    self:releaseDrags()
    dialog:openDialog()
end

--- restores focus once the last dialog closes
---@param dialog table
function Options:afterDialog(dialog)
    if dialog and not self:activeDialog() then
        self.group:refresh()
        self:revealFocus()
    end
end

---@param event string
---@param ... any
---@return boolean handled # a dialog took it
function Options:toDialog(event, ...)
    local dialog = self:activeDialog()
    if not dialog then return false end
    dialog[event](dialog, ...)
    self:afterDialog(dialog)
    return true
end

---@param dt number
function Options:update(dt)
    if self.layoutLanguage ~= I18n.current then self:layout() end
    local dialog = self:activeDialog()
    if dialog then
        dialog:update(dt)
        self:afterDialog(dialog)
        self.pointer:hover(dialog)
        return
    end
    self.scroll:update(dt)
    self.group:update(dt)
    self.pointer:hover(self.group, self.scroll:overScrollbar(self.pointer.x, self.pointer.y))
end

function Options:keypressed(key)
    self.keyboardInput = true
    if self:toDialog("keypressed", key) then return end
    self:releaseDrags()
    if key == "escape" then return self:goBack() end
    if key == "pageup" or key == "pagedown" then
        return Paging.page(self.scroll, self.group, key == "pageup" and -1 or 1)
    end
    self.group:keypressed(key)
    self:revealFocus(true)
end

function Options:mousepressed(x, y, button)
    self.pointer:move(x, y)
    self.keyboardInput = false
    if self:toDialog("mousepressed", x, y, button) or self.group.capture then return end
    self.scroll:setScroll(self.scroll.scrollY) -- rows hold still under a click
    if self.scroll:mousepressed(x, y, button) then return end
    self.group:mousepressed(x, y, button)
end

function Options:mousereleased(x, y, button)
    if self:toDialog("mousereleased", x, y, button) then return end
    self.scroll:mousereleased(x, y, button)
    self.group:mousereleased(x, y, button)
end

function Options:mousemoved(x, y)
    self.pointer:move(x, y)
    self.keyboardInput = false
    if self:toDialog("mousemoved", x, y) then return end
    if self.scroll:mousemoved(x, y) then return end
    self.group:mousemoved(x, y)
end

function Options:wheelmoved(_, y)
    if self:activeDialog() or self.group.capture or self.scroll.scrollbar:isDragging() then return end
    if not self.scroll:contains(self.pointer.x, self.pointer.y) then return end
    self.keyboardInput = false
    self.scroll:wheelmoved(y)
end

---@param rect table
---@param text string
---@param color number[]
local function note(rect, text, color)
    UI.Label.draw{ text = text, x = rect.x, y = rect.y, width = rect.w,
        font = UI.Theme.font("small"), color = color }
end

function Options:draw()
    local c, panel = UI.Theme.colors, self.panel
    UI.Label.draw{ text = I18n.t("options.title"), y = self.headingY, font = UI.Theme.font("heading") }
    self.tabBar:draw()
    UI.Theme.panel(panel.x, panel.y, panel.w, panel.h)
    self.scroll:draw()
    for _, button in ipairs(self:footerButtons()) do button:draw() end

    if self.graphics:isDirty() then note(self.statusRect, I18n.t("options.pendingGraphics"), c.warning) end
    note(self.hintRect, I18n.t("options.hint.navigation"), c.textDim)

    local dialog = self:activeDialog()
    if dialog then dialog:draw() end
end

return Options
