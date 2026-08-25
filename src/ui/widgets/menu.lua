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

function Menu:playIntro()
    if Motion.reduced then return end -- reduced motion: buttons are just there, no cascade
    self.introTime = 0
    for _, button in ipairs(self:buttons()) do
        button.introAlpha = 0
    end
end

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
