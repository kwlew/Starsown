-- F3 dev overlay; a singleton since main.lua drives just the one.
--
-- F3 also carries chords (F3 + P and so on, as Minecraft does). That is why
-- the overlay toggles on the *release* of F3 rather than the press: pressing
-- it on the way down would flash the panel on and off underneath every chord.
-- A chord is reported back to main.lua, which routes it to the current state
-- as chordpressed(key) -- Debug itself has no idea what any chord means.

local Theme = require "ui.core.theme"
local Math = require "utils.math"

local Debug = {
    fps = 0,
    memory = 0,
    latency = 0,
    visible = false,
}

-- read straight off the keyboard rather than tracked through keypressed, so an
-- F3 release swallowed by a lost window focus can't leave chording stuck on
local function chording()
    return love.keyboard.isDown("f3")
end

local chorded = false -- something was pressed while F3 was held

-- returns (consumed, chordKey). main.lua sends chordKey on to the current
-- state; anything else consumed is F3 itself and goes no further.
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

function Debug.keyreleased(key)
    if key ~= "f3" then return false end
    if not chorded then Debug.toggle() end
    return true
end

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
