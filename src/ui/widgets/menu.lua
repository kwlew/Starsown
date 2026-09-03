local Theme = require "ui.core.theme"
local Button = require "ui.widgets.button"
local FocusGroup = require "ui.widgets.focusGroup"
local Ease = require "utils.ease"
local Math = require "utils.math"
local Motion = require "ui.core.motion"

local Menu = {}
Menu.__index = Menu

local INTRO_DURATION = 1.2
local INTRO_STAGGER = 0.01

--- a vertical column of Buttons over a FocusGroup -- the layout every screen
-- with a list of choices uses
---@param items table[] # { label: string|fun(self: table): string, onSelect?: fun(self: table), enabled?: boolean, danger?: boolean }[]
---@param font? any # a love.Font or a role name; defaults to the "button" role
---@return table
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

---@return any # a love.Font
function Menu:getFont()
    return Theme.fontFor(self.font, "button")
end

---@return table[]
function Menu:buttons()
    return self.group.widgets
end

---@param index integer
function Menu:setFocus(index)
    self.group:setFocus(index)
end

--- fn(widget, index) fires when the player moves the focus, not when the menu is built
---@param fn fun(widget: table, index: integer)
function Menu:onFocusChanged(fn)
    self.group.onFocusChanged = fn
end

--- centres the column and sizes every button to the widest label, so one long
-- translation widens the whole menu rather than truncating
---@param y number # top of the first row
---@param spacing? number # row pitch, defaults to rowHeight + rowGap
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

--- fades the buttons in, staggered top to bottom; a no-op under reduced motion
function Menu:playIntro()
    if Motion.reduced then return end -- reduced motion: buttons are just there, no cascade
    self.introTime = 0
    for _, button in ipairs(self:buttons()) do
        button.introAlpha = 0
    end
end

---@param dt number
function Menu:update(dt)
    self.group:update(dt)

    if self.introTime then
        self.introTime = self.introTime + dt
        local finished = true
        for i, button in ipairs(self:buttons()) do
            local t = (self.introTime - (i - 1) * INTRO_STAGGER) / INTRO_DURATION
            if t < 1 then finished = false end
            button.introAlpha = Ease.outCubic(Math.clamp01(t))
        end
        if finished then self.introTime = nil end
    end
end

--- pass-throughs to the group
function Menu:draw()              self.group:draw()                  end
function Menu:keypressed(key)     return self.group:keypressed(key)  end
function Menu:mousemoved(x, y)    return self.group:mousemoved(x, y) end

---@param x number
---@param y number
---@param button integer
---@return boolean consumed
function Menu:mousepressed(x, y, button)
    return self.group:mousepressed(x, y, button)
end

---@param x number
---@param y number
---@param button integer
---@return boolean consumed
function Menu:mousereleased(x, y, button)
    return self.group:mousereleased(x, y, button)
end

---@param x number
---@param y number
---@return boolean hovering
---@return boolean? danger
function Menu:hovering(x, y)
    return self.group:hovering(x, y)
end

return Menu
