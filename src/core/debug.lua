local Theme = require "ui.core.theme"
local Math = require "utils.math"

local Debug = {
    fps = 0,
    memory = 0,
    latency = 0,
    visible = false,
}

---@return boolean # true while F3 is held
---@nodiscard
local function chording()
    return love.keyboard.isDown("f3")
end

local chorded = false

--- F3's own press is swallowed (the overlay toggles on release instead, so a
-- chord doesn't flash it), and any other key pressed while F3 is held comes
-- back as a chord for the current state to handle instead of a normal press
---@param key string
---@param isrepeat boolean
---@return boolean handled
---@return string? # the chord key to route to the state's chordpressed
function Debug.keypressed(key, isrepeat)
    if key == "f3" then
        if not isrepeat then chorded = false end
        return true
    end
    if chording() then
        chorded = true
        return true, key
    end
    return false
end

--- toggles the overlay on F3's release, unless the hold was used as a chord
---@param key string
---@return boolean handled
function Debug.keyreleased(key)
    if key ~= "f3" then return false end
    if not chorded then Debug.toggle() end
    return true
end

---@return boolean visible
function Debug.toggle()
    Debug.visible = not Debug.visible
    return Debug.visible
end

--- the project's degrade-don't-crash path: a native message box for a failure
-- worth telling the player about
---@param message string
function Debug.error(message)
    love.window.showMessageBox("Error", message, "error")
end

--- samples fps/memory/latency, only while the overlay is up
function Debug:update()
    if not Debug.visible then return end
    Debug.fps = love.timer.getFPS()
    Debug.memory = Math.round(collectgarbage("count")) -- KB
    Debug.latency = Math.round(love.timer.getDelta() * 1000)
end

--- the F3 panel, top left; game/debugOverlay.lua owns the play screen's own
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
