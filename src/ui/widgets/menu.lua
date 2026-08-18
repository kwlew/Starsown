-- Vertical menu: a layout container over UI.Button. Focus, keyboard
-- movement, and mouse routing come from a UI.FocusGroup -- this file is
-- only the "stack them centered, size to the widest label" part.
--
-- Each item is a table:
--   label    : string, OR a function -> string for live values
--   onSelect : function called when the item is activated
--   enabled  : optional, false for a greyed-out entry (skipped by navigation)
--   danger   : optional, true for an entry that destroys something
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

local Theme = require "ui.core.theme"
local Button = require "ui.widgets.button"
local FocusGroup = require "ui.widgets.focusGroup"

local Menu = {}
Menu.__index = Menu

-- `font` is a Theme role name (or a Font object); resolved per draw so a rescale is picked up without a rebuild
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

-- fn(widget, index) fires when the player moves the focus, not when the menu is built
function Menu:onFocusChanged(fn)
    self.group.onFocusChanged = fn
end

-- lays buttons out centered, starting at y; all buttons share one width
-- (widest label wins). Called from the owning screen's layout(), not draw --
-- hit-testing needs current geometry, and label widths change with language/scale.
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

function Menu:mousepressed(x, y, button)
    return self.group:mousepressed(x, y, button)
end

function Menu:mousereleased(x, y, button)
    return self.group:mousereleased(x, y, button)
end

function Menu:hovering(x, y)
    return self.group:hovering(x, y)
end

return Menu
