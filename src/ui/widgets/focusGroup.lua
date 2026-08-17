-- src/ui/focusGroup.lua
-- Owns a list of widgets and the one thing every screen kept reimplementing:
-- which widget has focus, how the keyboard moves it, and where a mouse event
-- goes. Options and Menu each had their own copy of this, and Options also
-- carried a hand-maintained list of its sliders purely so a drag could keep
-- tracking after the cursor left the widget's rect — a widget concern that had
-- leaked into a screen. That is generic mouse capture, and it lives here now.
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
-- subsequent move and the release, wherever the cursor goes. That is what lets
-- a slider drag continue off the end of its row, and what stops focus from
-- wandering to whatever the cursor passes over mid-drag.
--
-- The input methods return true when the event was consumed, so a screen can
-- act on the ones the group ignored (Esc, a click on empty background).

local Math = require "utils.math"

local FocusGroup = {}
FocusGroup.__index = FocusGroup

function FocusGroup.new()
    return setmetatable({
        widgets = {},
        index = 0,     -- 0 = nothing focused (empty or all-disabled group)
        capture = nil, -- widget owning the mouse until it releases
        -- Optional onFocusChanged(widget, index), set by the owning screen.
        -- Fires only when the player moves the focus, never when the list is
        -- rebuilt underneath it — see the `silent` argument below.
        onFocusChanged = nil,
    }, FocusGroup)
end

-- Replaces the whole list — what a tab switch does. Any in-flight drag is
-- dropped, since the widget that owned it may not be on screen anymore.
function FocusGroup:setWidgets(widgets)
    self.widgets = widgets
    self.capture = nil
    -- Silent: rebuilding the list is the screen reconfiguring itself, not the
    -- player navigating, and the caller has usually just played its own sound
    -- for whatever caused it.
    self:focusFirst(true)
end

function FocusGroup:focused()
    return self.widgets[self.index]
end

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

function FocusGroup:focusFirst(silent)
    for i, widget in ipairs(self.widgets) do
        if widget:isInteractive() then
            self:setFocus(i, silent)
            return
        end
    end
    self:setFocus(0, silent) -- nothing here can take focus
end

-- Moves focus by delta, wrapping and skipping anything not interactive. The
-- loop is bounded by the widget count rather than "until we're back where we
-- started": from an unfocused group (index 0) that comparison never comes true
-- and would spin forever.
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

-- Re-checks the current focus after something has toggled a widget's `enabled`
-- flag. Focus left sitting on a row that just went inert reads as "nothing is
-- selected": the glow eases out and the arrow keys do nothing until the player
-- moves off it. Pressing Enter on Options' Apply button does exactly this —
-- committing the change is what greys the button out.
function FocusGroup:refresh()
    local widget = self:focused()
    if widget and not widget:isInteractive() then
        self:moveFocus(1)
    end
end

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

function FocusGroup:mousemoved(x, y)
    -- A widget mid-drag owns the mouse: it keeps receiving moves even once the
    -- cursor has left its rect, and focus doesn't wander to whatever it passes
    -- over on the way.
    if self.capture then
        if self.capture.mousemoved then self.capture:mousemoved(x, y) end
        return true
    end

    -- Hover feedback for widgets that track the cursor (selector chevrons, tab
    -- segments). Widgets without hover state simply don't implement this.
    for _, widget in ipairs(self.widgets) do
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

-- A press on a disabled widget is still consumed: it's an inert control, not a
-- hole through to whatever is behind the screen.
function FocusGroup:mousepressed(x, y, button)
    for i, widget in ipairs(self.widgets) do
        if widget:contains(x, y) then
            if widget:isInteractive() then
                self:setFocus(i)
                if widget:mousepressed(x, y, button) then
                    self.capture = widget -- asked to own the mouse until release
                end
            end
            return true
        end
    end
    return false
end

function FocusGroup:mousereleased(x, y, button)
    local target = self.capture
    if not target then return false end

    self.capture = nil
    if target.mousereleased then target:mousereleased(x, y, button) end
    return true
end

-- Is the cursor over something interactive? Screens use this to drive the
-- cursor. It has to be a query rather than a side effect of mousemoved,
-- because the answer is needed every frame — see src/ui/cursor.lua.
--
-- Second return is the hovered widget's `danger` flag, so a screen can pass
-- both straight to UI.Cursor.setHover without checking which widget it was.
function FocusGroup:hovering(x, y)
    for _, widget in ipairs(self.widgets) do
        if widget:isInteractive() and widget:contains(x, y) then
            return true, widget.danger
        end
    end
    return false
end

function FocusGroup:update(dt)
    for _, widget in ipairs(self.widgets) do
        widget:update(dt)
    end
end

-- Draws every widget in list order. Screens that interleave their widgets with
-- other art (Options draws a panel behind its rows) skip this and draw the
-- widgets themselves; the group is about focus and routing, not painting.
function FocusGroup:draw()
    for _, widget in ipairs(self.widgets) do
        widget:draw()
    end
end

return FocusGroup
