-- src/ui/core/cursor.lua

local Theme = require "ui.core.theme"
local Motion = require "ui.core.motion"
local Globals = require "globals";

local Cursor = {}

local RADIUS = Globals.cursor.size

local OUTLINE_WIDTH = 0.5
local HOVER_OUTLINE_WIDTH = 1

local CLICK_GROWTH = 3
local CLICK_LIFE = 0.25

local hovering = false
local danger = false
local current = { 1, 1, 1 }
local currentOutline = { Theme.colors.shadow[1], Theme.colors.shadow[2], Theme.colors.shadow[3] }
local enabled = true
local outlineWidth = OUTLINE_WIDTH
local wasDown = false
local click = nil

function Cursor.init()
    Cursor.setEnabled(true) 
end

function Cursor.setEnabled(isEnabled)
    enabled = isEnabled
    love.mouse.setVisible(not enabled)
end

function Cursor.setHover(isHovering, isDanger)
    hovering = isHovering
    danger = isDanger or false
end

function Cursor.update(dt)
    local target = Theme.colors.cursor
    if hovering then
        target = danger and Theme.colors.danger or Theme.colors.accent
    end
    current[1] = Theme.approach(current[1], target[1], dt)
    current[2] = Theme.approach(current[2], target[2], dt)
    current[3] = Theme.approach(current[3], target[3], dt)

    local outlineTarget = hovering and Theme.colors.highlight or Theme.colors.shadow
    currentOutline[1] = Theme.approach(currentOutline[1], outlineTarget[1], dt)
    currentOutline[2] = Theme.approach(currentOutline[2], outlineTarget[2], dt)
    currentOutline[3] = Theme.approach(currentOutline[3], outlineTarget[3], dt)

    outlineWidth = Theme.approach(outlineWidth, hovering and HOVER_OUTLINE_WIDTH or OUTLINE_WIDTH, dt)

    local isDown = enabled and love.mouse.isDown(1)
    if isDown and not wasDown and not Motion.reduced then click = 0 end
    wasDown = isDown
    if click then
        click = click + dt
        if click >= CLICK_LIFE then click = nil end
    end
end

function Cursor.draw()
    if not enabled then return end

    local x, y = love.mouse.getPosition()
    local radius = Theme.px(RADIUS)

    if click then
        local t = click / CLICK_LIFE
        Theme.setColor(current, 1 - t)
        love.graphics.setLineWidth(math.max(1, Theme.px(OUTLINE_WIDTH)))
        love.graphics.circle("line", x, y, radius + Theme.px(CLICK_GROWTH) * t, 16)
    end

    love.graphics.setColor(current[1], current[2], current[3], 1)
    love.graphics.circle("fill", x, y, radius, 6)

    Theme.setColor(currentOutline)
    love.graphics.setLineWidth(math.max(1, Theme.px(outlineWidth)))
    love.graphics.circle("line", x, y, radius, 32)
    love.graphics.setLineWidth(1)

    love.graphics.setColor(1, 1, 1, 1)
end

return Cursor
