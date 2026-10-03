--- The F3 panel: engine numbers and each service's status.

local App = require("core.app")
local Diagnostics = require("lib.diagnostics")
local Math = require("utils.math")
local Theme = require("ui.core.theme")

local Overlay = {
    visible = false,
    fps = 0,
    memory = 0,
    latency = 0,
}

local MARGIN = 4
local LINE_GAP = 2

---@return boolean visible
function Overlay.toggle()
    Overlay.visible = not Overlay.visible
    return Overlay.visible
end

--- samples only while shown
function Overlay.update()
    if not Overlay.visible then return end
    Overlay.fps = love.timer.getFPS()
    Overlay.memory = Math.round(collectgarbage("count"))
    Overlay.latency = Math.round(love.timer.getDelta() * 1000)
end

---@return string[]
local function lines()
    local list = {
        App.NAME .. " " .. App.VERSION,
        "FPS: " .. Overlay.fps,
        "Memory: " .. Overlay.memory .. " KB",
        "Latency: " .. Overlay.latency .. " ms",
        "",
    }
    for _, line in ipairs(Diagnostics.lines()) do list[#list + 1] = line end
    return list
end

function Overlay.draw()
    if not Overlay.visible then return end
    local font = Theme.font("debug")
    local lineHeight = font:getHeight() + LINE_GAP

    Theme.pushFont(font)
    Theme.setColor(Theme.colors.textDim)
    for i, line in ipairs(lines()) do
        love.graphics.print(line, MARGIN, LINE_GAP + lineHeight * (i - 1))
    end
    Theme.popFont()
    love.graphics.setColor(1, 1, 1, 1)
end

return Overlay
