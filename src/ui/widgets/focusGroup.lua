--- Owns a list of widgets and the thing every screen kept reimplementing:
-- which widget has focus, how the keyboard moves it, and where a mouse
-- event goes. Also owns generic mouse capture, so a drag can keep tracking
-- after the cursor leaves the widget's rect.
--
--   self.group = FocusGroup.new()
--   self.group:setWidgets{ tabBar, slider, selector, backButton }
--
--   function State:update(dt)              self.group:update(dt)              end
--   function State:keypressed(key)         self.group:keypressed(key)         end
--   function State:mousemoved(x, y)        self.group:mousemoved(x, y)        end
--   function State:mousepressed(x, y, b)   self.group:mousepressed(x, y, b)   end
--   function State:mousereleased(x, y, b)  self.group:mousereleased(x, y, b)  end
--
-- Mouse capture: a widget whose `mousepressed` returns true owns every
-- subsequent move and the release, wherever the cursor goes -- lets a
-- slider drag continue off the end of its row without focus wandering.
--
-- Input methods return true when the event was consumed, so a screen can
-- act on the ones the group ignored (Esc, a click on empty background).

local Math = require "utils.math"

local FocusGroup = {}
FocusGroup.__index = FocusGroup

---@return table
function FocusGroup.new()
    return setmetatable({
        widgets = {},
        index = 0,     -- 0 = nothing focused (empty or all-disabled group)
        capture = nil, -- widget owning the mouse until it releases
        onFocusChanged = nil, -- optional onFocusChanged(widget, index); fires only on player-driven moves
    }, FocusGroup)
end

--- replaces the whole list (a tab switch); any in-flight drag is dropped, its owner may not be on screen anymore
---@param widgets table[] # each must answer contains/update/draw/enabled
function FocusGroup:setWidgets(widgets)
    self.widgets = widgets
    self.capture = nil
    self:focusFirst(true) -- silent: this is the screen reconfiguring itself, not the player navigating
end

---@return table|nil
function FocusGroup:focused()
    return self.widgets[self.index]
end

---@param index integer # 0 clears focus
---@param silent? boolean # suppress onFocusChanged (a screen reconfiguring itself, not the player navigating)
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
        if widget:isInteractive() then
            self:setFocus(i, silent)
            return
        end
    end
    self:setFocus(0, silent)
end

--- bounded by widget count, not "until we're back where we started": from an
-- unfocused group (index 0) that never comes true and would spin forever
--- wraps past either end, skipping anything not interactive
---@param delta -1|1
function FocusGroup:moveFocus(delta)
    local count = #self.widgets
    if count == 0 then return end

    local index = self.index
    for _ = 1, count do
        index = Math.wrapIndex(index + delta, count)
        if self.widgets[index]:isInteractive() then
            self:setFocus(index)
            return
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

--- up/down move focus; left/right and Enter go to the focused widget's own
-- adjust/activate, if it has them
---@param key string
---@return boolean consumed
function FocusGroup:keypressed(key)
    if key == "up" or key == "w" then
        self:moveFocus(-1)
        return true
    elseif key == "down" or key == "s" then
        self:moveFocus(1)
        return true
    end

    local widget = self:focused()
    if not (widget and widget:isInteractive()) then return false end

    if key == "left" or key == "a" then
        if widget.adjust then widget:adjust(-1) return true end
    elseif key == "right" or key == "d" then
        if widget.adjust then widget:adjust(1) return true end
    elseif key == "return" or key == "kpenter" or key == "space" then
        if widget.activate then widget:activate() return true end
    end
    return false
end

--- hover follows the pointer, and moving over a widget focuses it -- unless a
-- drag holds the mouse, in which case focus stays put
---@param x number
---@param y number
---@return boolean consumed
function FocusGroup:mousemoved(x, y)
    if self.capture then -- a widget mid-drag owns the mouse; focus doesn't wander mid-drag
        if self.capture.mousemoved then self.capture:mousemoved(x, y) end
        return true
    end

    for _, widget in ipairs(self.widgets) do -- hover feedback (selector chevrons, tab segments)
        if widget.mousemoved then widget:mousemoved(x, y) end
    end

    for i, widget in ipairs(self.widgets) do
        if widget:isInteractive() and widget:contains(x, y) then
            self:setFocus(i)
            return true
        end
    end
    return false
end

--- a press on a disabled widget is still consumed: it's inert, not a hole through to what's behind the screen
---@param x number
---@param y number
---@param button integer
---@return boolean consumed
function FocusGroup:mousepressed(x, y, button)
    for i, widget in ipairs(self.widgets) do
        if widget:contains(x, y) then
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
    if not target then return false end

    self.capture = nil
    if target.mousereleased then target:mousereleased(x, y, button) end
    return true
end

--- second return is the hovered widget's `danger` flag, so a screen can pass
-- both straight to UI.Cursor.setHover
---@param x number
---@param y number
---@return boolean hovering
---@return boolean? danger
function FocusGroup:hovering(x, y)
    for _, widget in ipairs(self.widgets) do
        if widget:isInteractive() and widget:contains(x, y) then
            return true, widget.danger
        end
    end
    return false
end

---@param dt number
function FocusGroup:update(dt)
    for _, widget in ipairs(self.widgets) do
        widget:update(dt)
    end
end

--- screens that interleave widgets with other art (Options draws a panel
-- behind its rows) skip this and draw widgets themselves
function FocusGroup:draw()
    for _, widget in ipairs(self.widgets) do
        widget:draw()
    end
end

return FocusGroup
