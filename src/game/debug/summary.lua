--- F3+G, on screen: entity counts and the cursor's tile.

local Tile = require("game.tile")
local UI = require("ui")

local Summary = {}

local MARGIN = 20

---@param world table
---@return string
local function counts(world)
    local tally, order = {}, {}
    for e in world:each() do
        if not tally[e.kind] then order[#order + 1] = e.kind end
        tally[e.kind] = (tally[e.kind] or 0) + 1
    end
    table.sort(order)
    local parts = {}
    for _, kind in ipairs(order) do parts[#parts + 1] = ("%s %d"):format(kind, tally[kind]) end
    parts[#parts + 1] = ("effects %d"):format(#world.effects)
    return table.concat(parts, "  ")
end

--- bottom-left, screen space
---@param world table
---@param camera table
function Summary.draw(world, camera)
    local wx, wy = camera:toWorld(love.mouse.getPosition())
    local lines = {
        "F3+G debug view",
        counts(world),
        ("cursor %d, %d  tile %d, %d"):format(wx, wy, math.floor(wx / Tile.SIZE), math.floor(wy / Tile.SIZE)),
    }
    local Theme = UI.Theme
    local font = Theme.font("small")
    local lineH, margin = font:getHeight(), Theme.px(MARGIN)
    local y = love.graphics.getHeight() - margin - lineH * #lines
    for i, text in ipairs(lines) do
        UI.Label.draw{ text = text, x = margin, y = y + (i - 1) * lineH, align = "left",
            font = font, shadow = true, color = i == 1 and Theme.colors.accent or Theme.colors.text }
    end
end

return Summary
