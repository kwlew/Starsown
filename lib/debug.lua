local Theme = require "lib.ui.theme"

local Debug = {}

function Debug:new()
    local obj = {
        fps = 0,
        memory = 0,
        latency = 0
    }
    setmetatable(obj, { __index = self })
    return obj
end

function Debug.getFPS()
    Debug.fps = love.timer.getFPS()
end

function Debug.getMemory()
    Debug.memory = math.floor(collectgarbage("count") + 0.5) -- Convert to bytes
end

function Debug.getLatency()
    Debug.latency = math.floor(love.timer.getDelta() * 1000 + 0.5) -- Convert to milliseconds
end

function Debug.error(message)
    love.window.showMessageBox("Error", message, "error")
end

function Debug:update()
    Debug.getFPS()
    Debug.getMemory()
    Debug.getLatency()
end

function Debug:draw()
    local previousFont = love.graphics.getFont()
    local font = Theme.font("small")
    local lineHeight = font:getHeight() + 2

    love.graphics.setFont(font)
    love.graphics.setColor(Theme.colors.textDim)
    love.graphics.printf("FPS: " .. Debug.fps, 4, 2, love.graphics.getWidth(), "left")
    love.graphics.printf("Memory: " .. Debug.memory .. " KB", 4, 2 + lineHeight, love.graphics.getWidth(), "left")
    love.graphics.printf("Latency: " .. Debug.latency .. " ms", 4, 2 + lineHeight * 2, love.graphics.getWidth(), "left")

    love.graphics.setFont(previousFont)
    love.graphics.setColor(1, 1, 1, 1)
end

return Debug
