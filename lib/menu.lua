-- lib/menu.lua
-- Vertical menu: a thin layout container over UI.Button that unifies keyboard
-- focus and mouse hover into one `selected` index.
--
-- Each item is a table:
--   label    : string, OR a function -> string for live values
--   onSelect : function called when the item is activated
--
-- Usage:
--   self.menu = Menu.new({
--       { label = "Play",    onSelect = function() ... end },
--       { label = "Options", onSelect = function() ... end },
--   })
--
--   function State:update(dt)               self.menu:update(dt)              end
--   function State:keypressed(key)          self.menu:keypressed(key)         end
--   function State:mousemoved(x, y)         self.menu:mousemoved(x, y)        end
--   function State:mousepressed(x, y, btn)  self.menu:mousepressed(x, y, btn) end
--   function State:draw()                   self.menu:draw(320)               end

local Theme = require "lib.ui.theme"
local Button = require "lib.ui.button"

local Menu = {}
Menu.__index = Menu

function Menu.new(items, font)
    local self = setmetatable({
        buttons = {},
        selected = 1,
        font = font or Theme.font("body"),
        minWidth = 280,
    }, Menu)

    for _, item in ipairs(items) do
        self.buttons[#self.buttons + 1] = Button.new{
            label = item.label,
            onSelect = item.onSelect,
            font = self.font,
        }
    end

    self:setFocus(1)
    self.buttons[1].glow = 1 -- first frame already shows the focus

    return self
end

function Menu:setFocus(index)
    self.selected = index
    for i, button in ipairs(self.buttons) do
        button.focused = (i == index)
    end
end

-- Moves the focus by delta, wrapping around the ends.
function Menu:move(delta)
    local count = #self.buttons
    self:setFocus((self.selected - 1 + delta) % count + 1)
end

function Menu:activate()
    local button = self.buttons[self.selected]
    if button then
        button:activate()
    end
end

function Menu:keypressed(key)
    if key == "up" or key == "w" then
        self:move(-1)
    elseif key == "down" or key == "s" then
        self:move(1)
    elseif key == "return" or key == "kpenter" or key == "space" then
        self:activate()
    end
end

-- Hover focuses the button under the cursor; off any button, the current
-- focus is kept (so keyboard and mouse coexist without flicker).
function Menu:mousemoved(x, y)
    for i, button in ipairs(self.buttons) do
        if button:contains(x, y) then
            self:setFocus(i)
            return
        end
    end
end

function Menu:mousepressed(x, y, mouseButton)
    if mouseButton ~= 1 then return end
    for i, button in ipairs(self.buttons) do
        if button:contains(x, y) then
            self:setFocus(i)
            button:activate()
            return
        end
    end
end

function Menu:mousereleased(x, y, mouseButton) -- luacheck: no unused
    -- No-op today; kept so states can forward it uniformly.
end

function Menu:update(dt)
    for _, button in ipairs(self.buttons) do
        button:update(dt)
    end
end

-- Lays the buttons out centered horizontally starting at y, then draws them.
-- All buttons share one width (widest label wins) so the column reads as a
-- unit. spacing is the vertical step between button tops.
function Menu:draw(y, spacing)
    local m = Theme.metrics
    spacing = spacing or (m.rowHeight + m.rowGap)

    local width = self.minWidth
    for _, button in ipairs(self.buttons) do
        width = math.max(width, self.font:getWidth(button:labelText()) + m.padding * 4)
    end

    local x = (love.graphics.getWidth() - width) / 2
    for i, button in ipairs(self.buttons) do
        button.x = x
        button.y = y + (i - 1) * spacing
        button.w = width
        button:draw()
    end
end

return Menu
