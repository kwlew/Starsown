-- src/ui/menu.lua
-- Vertical menu: a layout container over UI.Button. Focus, keyboard movement,
-- and mouse routing all come from a UI.FocusGroup — this file is only the
-- "stack them centered and size them to the widest label" part.
--
-- Each item is a table:
--   label    : string, OR a function -> string for live values
--   onSelect : function called when the item is activated
--   enabled  : optional, false for a greyed-out entry (skipped by navigation)
--   danger   : optional, true for an entry that destroys something (it lights
--              up in the theme's danger red rather than its accent)
--
-- Usage:
--   self.menu = Menu.new({
--       { label = "Play",    onSelect = function() ... end },
--       { label = "Options", onSelect = function() ... end },
--   })
--
--   function State:layout()                 self.menu:layout(320)             end
--   function State:update(dt)               self.menu:update(dt)              end
--   function State:keypressed(key)          self.menu:keypressed(key)         end
--   function State:mousemoved(x, y)         self.menu:mousemoved(x, y)        end
--   function State:mousepressed(x, y, btn)  self.menu:mousepressed(x, y, btn) end
--   function State:draw()                   self.menu:draw()                  end

local Theme = require "ui.theme"
local Button = require "ui.button"
local FocusGroup = require "ui.focusGroup"

local Menu = {}
Menu.__index = Menu

-- `font` is a Theme role name (or a Font object); resolved per draw so a
-- Theme.rescale is picked up without rebuilding the menu.
function Menu.new(items, font)
    local self = setmetatable({
        group = FocusGroup.new(),
        font = font or "button",
        minWidth = 280, -- design-space px, scaled through Theme.px at use
    }, Menu)

    local buttons = {}
    for _, item in ipairs(items) do
        buttons[#buttons + 1] = Button.new{
            label = item.label,
            onSelect = item.onSelect,
            enabled = item.enabled ~= false,
            danger = item.danger,
            font = self.font,
        }
    end
    self.group:setWidgets(buttons)

    local first = self.group:focused()
    if first then first.glow = 1 end -- first frame already shows the focus

    return self
end

function Menu:getFont()
    return Theme.fontFor(self.font, "button")
end

function Menu:buttons()
    return self.group.widgets
end

function Menu:setFocus(index)
    self.group:setFocus(index)
end

-- fn(widget, index) fires when the player moves the focus, not when the menu is
-- built. Screens use it for the navigation blip.
function Menu:onFocusChanged(fn)
    self.group.onFocusChanged = fn
end

-- Lays the buttons out centered horizontally starting at y. All buttons share
-- one width (widest label wins) so the column reads as a unit; `spacing` is the
-- vertical step between button tops.
--
-- Called from the owning screen's layout(), not from draw: hit-testing has to
-- work off geometry that's already current, and label widths change with the
-- active language and the UI scale.
function Menu:layout(y, spacing)
    local m = Theme.metrics
    local font = self:getFont()
    spacing = spacing or (m.rowHeight + m.rowGap)

    local width = Theme.px(self.minWidth)
    for _, button in ipairs(self:buttons()) do
        width = math.max(width, font:getWidth(button:labelText()) + m.padding * 4)
    end

    local x = (love.graphics.getWidth() - width) / 2
    for i, button in ipairs(self:buttons()) do
        button:setBounds(x, y + (i - 1) * spacing, width, m.rowHeight)
    end
end

function Menu:update(dt)          self.group:update(dt)              end
function Menu:draw()              self.group:draw()                  end
function Menu:keypressed(key)     return self.group:keypressed(key)  end
function Menu:mousemoved(x, y)    return self.group:mousemoved(x, y) end

-- Returns true when the click landed on a button, so callers can tell whether
-- the menu consumed it before acting on the click themselves.
function Menu:mousepressed(x, y, button)
    return self.group:mousepressed(x, y, button)
end

function Menu:mousereleased(x, y, button)
    return self.group:mousereleased(x, y, button)
end

-- Is the cursor over an interactive item? Screens use this to ask for the hand
-- cursor (see src/ui/cursor.lua for why it's a query, not a side effect).
function Menu:hovering(x, y)
    return self.group:hovering(x, y)
end

return Menu
