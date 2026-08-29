-- F3 dev overlay; a singleton since main.lua drives just the one

local Theme = require "ui.core.theme"
local Math = require "utils.math"

local Debug = {
    fps = 0,
    memory = 0,
    latency = 0,
    visible = false,
}

function Debug.toggle()
    Debug.visible = not Debug.visible
    return Debug.visible
end

function Debug.error(message)
    love.window.showMessageBox("Error", message, "error")
end

function Debug:update()
    if not Debug.visible then return end
    Debug.fps = love.timer.getFPS()
    Debug.memory = Math.round(collectgarbage("count")) -- KB
    Debug.latency = Math.round(love.timer.getDelta() * 1000)
end

function Debug:draw()
    if not Debug.visible then return end

    local font = Theme.font("debug")
    local lineHeight = font:getHeight() + 2
    local width = love.graphics.getWidth()

    Theme.pushFont(font)
    love.graphics.setColor(Theme.colors.textDim)
    love.graphics.printf("FPS: " .. Debug.fps, 4, 2, width, "left")
    love.graphics.printf("Memory: " .. Debug.memory .. " KB", 4, 2 + lineHeight, width, "left")
    love.graphics.printf("Latency: " .. Debug.latency .. " ms", 4, 2 + lineHeight * 2, width, "left")
    Theme.popFont()

    love.graphics.setColor(1, 1, 1, 1)
end

return Debug
