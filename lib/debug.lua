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
    love.graphics.printf("FPS: " .. Debug.fps, 0, 0, love.graphics.getWidth(), "left")
    love.graphics.printf("Memory: " .. Debug.memory .. " KB", 0, 20, love.graphics.getWidth(), "left")
    love.graphics.printf("Latency: " .. Debug.latency .. " ms", 0, 40, love.graphics.getWidth(), "left")
end

return Debug