--- A centred vertical column of Buttons over a FocusGroup -- the layout every
-- screen with a list of choices uses.
--
--   local menu = Menu.new{ { label = "Play", icon = "play", primary = true, onSelect = ... }, ... }
--   menu:layout(y)
--   menu:playIntro()

local Button = require("ui.widgets.button")
local FocusGroup = require("ui.widgets.focusGroup")
local Intro = require("ui.animation.intro")
local Theme = require("ui.core.theme")

local Menu = {}
Menu.__index = Menu

local MIN_WIDTH = 280 -- design px

---@param items table[] # { label: string|fun(self: table): string, onSelect?: fun(self: table), icon?: string, enabled?: boolean, danger?: boolean, primary?: boolean }[]
---@param font? any # a love.Font or a role name; defaults to the "button" role
---@return table
function Menu.new(items, font)
    local self = setmetatable({
        group = FocusGroup.new(),
        intro = Intro.new(),
        font = font or "button",
    }, Menu)

    local buttons = {}
    for _, item in ipairs(items) do
        buttons[#buttons + 1] = Button.new{
            label = item.label,
            onSelect = item.onSelect,
            enabled = item.enabled ~= false,
            danger = item.danger,
            primary = item.primary,
            icon = item.icon,
            font = self.font,
        }
    end
    self.group:setWidgets(buttons)

    local first = self.group:focused()
    if first then first.glow = 1 end -- the first frame already shows the focus

    return self
end

---@return table[]
function Menu:buttons()
    return self.group.widgets
end

---@param index integer
---@param silent? boolean # skip onFocusChanged, for focus the player didn't move
function Menu:setFocus(index, silent)
    self.group:setFocus(index, silent)
end

--- fires when the player moves the focus, not when the menu is built
---@param fn fun(widget: table, index: integer)
function Menu:onFocusChanged(fn)
    self.group.onFocusChanged = fn
end

--- centres the column and sizes every button to the widest label, so one
-- long translation widens the whole menu rather than truncating
---@param y number # top of the first row
---@param spacing? number # row pitch, defaults to rowHeight + rowGap
function Menu:layout(y, spacing)
    local m = Theme.metrics
    local font = Theme.fontFor(self.font, "button")
    spacing = spacing or (m.rowHeight + m.rowGap)

    local width = Theme.px(MIN_WIDTH)
    for _, button in ipairs(self:buttons()) do
        local icon = button.icon and m.rowHeight or 0 -- the icon column is one row-height square
        width = math.max(width, font:getWidth(button:labelText()) + m.padding * 4 + icon)
    end

    local x = (love.graphics.getWidth() - width) / 2
    for i, button in ipairs(self:buttons()) do
        button:setBounds(x, y + (i - 1) * spacing, width, m.rowHeight)
    end
end

--- fades the buttons in, staggered top to bottom
function Menu:playIntro()
    self.intro:play(self:buttons())
end

---@param dt number
function Menu:update(dt)
    self.group:update(dt)
    self.intro:update(dt)
end

function Menu:draw()                     self.group:draw()                           end
function Menu:keypressed(key)            return self.group:keypressed(key)           end
function Menu:mousemoved(x, y)           return self.group:mousemoved(x, y)          end
function Menu:mousepressed(x, y, b)      return self.group:mousepressed(x, y, b)     end
function Menu:mousereleased(x, y, b)     return self.group:mousereleased(x, y, b)    end
function Menu:hovering(x, y)             return self.group:hovering(x, y)            end

return Menu
