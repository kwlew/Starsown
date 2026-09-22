-- src/states/game/rendering/hotbar.lua
-- The row of quick slots above the status bar.

local Theme = require "ui.core.theme"
local Slot = require "states.game.rendering.slot"
local Hud = require "states.game.rendering.hud"

local Hotbar = {}

local BOTTOM_GAP = 10

--- Screen-space; call outside the camera transform.
---@param inventory table
function Hotbar.draw(inventory)
    local size, gap = Theme.px(Slot.SIZE), Theme.px(Slot.GAP)
    local count = inventory.hotbarSize
    local width = count * size + (count - 1) * gap
    local x = math.floor((love.graphics.getWidth() - width) / 2)
    local y = love.graphics.getHeight() - Hud.height() - Theme.px(BOTTOM_GAP) - size

    for i = 1, count do
        Slot.draw(x + (i - 1) * (size + gap), y, size, inventory:get(i),
            { selected = i == inventory.selected, label = tostring(i) })
    end
end

return Hotbar
