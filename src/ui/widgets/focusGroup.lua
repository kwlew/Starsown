--- Owns a list of widgets and routes input to them: which one has focus, how
-- the keyboard moves it, and where a mouse event goes. A widget whose
-- mousepressed returns true captures every later move and the release, so
-- a slider drag keeps tracking after the cursor leaves its row.
--
--   self.group = FocusGroup.new()
--   self.group:setWidgets{ tabBar, slider, selector, backButton }
--   -- forward update/draw/keypressed/mousemoved/mousepressed/mousereleased
--
-- Input methods return true when the event was consumed, so a screen can
-- act on the ones the group ignored (Esc, a click on empty background).

local Bindings = require("ui.input.bindings")
local Math = require("utils.math")

local FocusGroup = {}
FocusGroup.__index = FocusGroup

local OFFSCREEN = -math.huge -- a pointer position nothing contains, to clear hover state

---@return table
function FocusGroup.new()
    return setmetatable({
        widgets = {},
        index = 0,            -- 0 = nothing focused (empty or all-disabled group)
        capture = nil,        -- widget owning the mouse until it releases
        onFocusChanged = nil, -- fun(widget, index); fires only on player-driven moves
        pointerFilter = nil,  -- fun(widget, x, y) -> boolean; e.g. a ScrollArea's clip
    }, FocusGroup)
end

--- replaces the whole list (a tab switch); an in-flight drag is ended, its
-- owner may not be on screen anymore
---@param widgets table[]
function FocusGroup:setWidgets(widgets)
    self:releaseCapture()
    self.widgets = widgets
    self:focusFirst(true) -- silent: the screen reconfiguring itself, not the player navigating
end

--- ends a live drag before its owner disappears or a modal takes input
function FocusGroup:releaseCapture()
    local target = self.capture
    self.capture = nil
    if target and target.mousereleased then target:mousereleased(0, 0, 1) end
end

---@param widget table
---@param x number
---@param y number
---@return boolean
function FocusGroup:allowsPointer(widget, x, y)
    return not self.pointerFilter or self.pointerFilter(widget, x, y)
end

--- the first interactive widget under the pointer
---@param x number
---@param y number
---@return table|nil widget
---@return integer|nil index
function FocusGroup:widgetAt(x, y)
    for i, widget in ipairs(self.widgets) do
        if widget:isInteractive() and self:allowsPointer(widget, x, y) and widget:contains(x, y) then
            return widget, i
        end
    end
end

---@return table|nil
function FocusGroup:focused()
    return self.widgets[self.index]
end

---@param index integer # 0 clears focus
---@param silent? boolean # suppress onFocusChanged
function FocusGroup:setFocus(index, silent)
    local changed = index ~= self.index
    self.index = index
    for i, widget in ipairs(self.widgets) do
        widget.focused = (i == index)
    end
    if changed and not silent and self.onFocusChanged then
        self.onFocusChanged(self.widgets[index], index)
    end
end

--- focuses the first interactive widget, or nothing if there isn't one
---@param silent? boolean
function FocusGroup:focusFirst(silent)
    for i, widget in ipairs(self.widgets) do
        if widget:isInteractive() then return self:setFocus(i, silent) end
    end
    self:setFocus(0, silent)
end

--- wraps past either end, skipping anything not interactive. Bounded by the
-- widget count: from an unfocused group (index 0) "until we're back where we
-- started" would never come true.
---@param delta -1|1
function FocusGroup:moveFocus(delta)
    local count = #self.widgets
    local index = self.index
    for _ = 1, count do
        index = Math.wrapIndex(index + delta, count)
        if self.widgets[index]:isInteractive() then
            return self:setFocus(index)
        end
    end
end

--- re-checks focus after something toggled a widget's `enabled` -- a focused
-- row that just went inert would otherwise look selected but do nothing
function FocusGroup:refresh()
    local widget = self:focused()
    if widget and not widget:isInteractive() then
        self:moveFocus(1)
    end
end

--- up/down and tab move focus; left/right and confirm go to the focused
-- widget's adjust/activate, if it has them
---@param key string
---@return boolean consumed
function FocusGroup:keypressed(key)
    local action = Bindings.action(key)
    if action == "up" or action == "previous" then
        self:moveFocus(-1)
        return true
    elseif action == "down" or action == "next" then
        self:moveFocus(1)
        return true
    end

    local widget = self:focused()
    if not (widget and widget:isInteractive()) then return false end

    if (action == "left" or action == "right") and widget.adjust then
        widget:adjust(action == "left" and -1 or 1)
        return true
    elseif action == "confirm" and widget.activate then
        widget:activate()
        return true
    end
    return false
end

--- hover follows the pointer, and moving over a widget focuses it -- unless
-- a drag holds the mouse, in which case focus stays put
---@param x number
---@param y number
---@return boolean consumed
function FocusGroup:mousemoved(x, y)
    if self.capture then
        if self.capture.mousemoved then self.capture:mousemoved(x, y) end
        return true
    end

    for _, widget in ipairs(self.widgets) do -- hover feedback (selector chevrons, tab segments)
        if widget.mousemoved then
            if self:allowsPointer(widget, x, y) then
                widget:mousemoved(x, y)
            else
                widget:mousemoved(OFFSCREEN, OFFSCREEN)
            end
        end
    end

    local _, index = self:widgetAt(x, y)
    if index then
        self:setFocus(index)
        return true
    end
    return false
end

--- a press on a disabled widget is still consumed: it's inert, not a hole
-- through to whatever is behind the screen
---@param x number
---@param y number
---@param button integer
---@return boolean consumed
function FocusGroup:mousepressed(x, y, button)
    for i, widget in ipairs(self.widgets) do
        if self:allowsPointer(widget, x, y) and widget:contains(x, y) then
            if widget:isInteractive() then
                self:setFocus(i)
                if widget:mousepressed(x, y, button) then
                    self.capture = widget
                end
            end
            return true
        end
    end
    return false
end

--- ends a capture; without one there's nothing to release, so it's not consumed
---@param x number
---@param y number
---@param button integer
---@return boolean consumed
function FocusGroup:mousereleased(x, y, button)
    local target = self.capture
    if not target or button ~= 1 then return false end

    self.capture = nil
    if target.mousereleased then target:mousereleased(x, y, button) end
    return true
end

--- the second return is the hovered widget's danger flag, so a screen can
-- pass both straight to Cursor.setHover
---@param x number
---@param y number
---@return boolean hovering
---@return boolean danger
function FocusGroup:hovering(x, y)
    local widget = self:widgetAt(x, y)
    return widget ~= nil, widget ~= nil and widget.danger
end

---@param dt number
function FocusGroup:update(dt)
    for _, widget in ipairs(self.widgets) do
        widget:update(dt)
    end
end

--- screens that interleave widgets with other art draw them themselves instead
function FocusGroup:draw()
    for _, widget in ipairs(self.widgets) do
        widget:draw()
    end
end

return FocusGroup
