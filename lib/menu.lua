-- lib/menu.lua
-- Simple keyboard-driven vertical menu, shared by menu-like states so they
-- don't each reimplement navigation and drawing.
--
-- Each item is a table:
--   label    : string, OR a function(item) -> string for live values
--              (e.g. "Fullscreen: ON")
--   onSelect : function(item) called when the item is activated
--
-- Usage:
--   self.menu = Menu.new({
--       { label = "Play",    onSelect = function() ... end },
--       { label = "Options", onSelect = function() ... end },
--   }, Assets.get("menuFont"))
--
--   function State:keypressed(key) self.menu:keypressed(key) end
--   function State:draw()          self.menu:draw(320, 44)    end

local Menu = {}
Menu.__index = Menu

function Menu.new(items, font)
    return setmetatable({
        items = items,
        selected = 1,
        font = font, -- optional; falls back to the current graphics font
    }, Menu)
end

local function labelOf(item)
    if type(item.label) == "function" then
        return item.label(item)
    end
    return item.label
end

-- Moves the highlight by delta, wrapping around the ends.
function Menu:move(delta)
    local count = #self.items
    self.selected = (self.selected - 1 + delta) % count + 1
end

function Menu:activate()
    local item = self.items[self.selected]
    if item and item.onSelect then
        item.onSelect(item)
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

-- Draws the items centered horizontally, starting at y, spacing pixels apart.
function Menu:draw(y, spacing)
    spacing = spacing or 40
    local width = love.graphics.getWidth()

    local previousFont
    if self.font then
        previousFont = love.graphics.getFont()
        love.graphics.setFont(self.font)
    end

    for i, item in ipairs(self.items) do
        local text = labelOf(item)
        if i == self.selected then
            love.graphics.setColor(1, 0.85, 0.2, 1) -- highlight
            text = "> " .. text .. " <"
        else
            love.graphics.setColor(1, 1, 1, 1)
        end
        love.graphics.printf(text, 0, y + (i - 1) * spacing, width, "center")
    end

    love.graphics.setColor(1, 1, 1, 1)
    if previousFont then
        love.graphics.setFont(previousFont)
    end
end

return Menu
