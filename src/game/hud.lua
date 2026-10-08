--- The run overlay: health and stamina, bottom-left, screen space.

local Bar = require("game.hud.bar")
local Math = require("utils.math")
local UI = require("ui")

local Hud = {}
Hud.__index = Hud

local MARGIN = 24
local ROW_GAP = 4
local HEALTH_H = 22
local STAMINA_H = 10
local TEXT_PAD = 8
local FILL_SPEED = 8 -- smooths the 20 TPS steps

---@return table
function Hud.new()
    return setmetatable({ health = nil, stamina = nil }, Hud)
end

---@param value number
---@param max number
---@return number
local function fraction(value, max)
    return max > 0 and Math.clamp01(value / max) or 0
end

---@param shown number|nil
---@param target number
---@param dt number
---@return number
local function ease(shown, target, dt)
    return shown and UI.Theme.approach(shown, target, dt, FILL_SPEED) or target
end

--- only while unpaused, so bars freeze under the menu
---@param dt number
---@param player table|nil
function Hud:update(dt, player)
    if not player then return end
    self.health = ease(self.health, fraction(player.health, player.maxHealth), dt)
    self.stamina = ease(self.stamina, fraction(player.stamina.value, player.stamina.max), dt)
end

---@param player table|nil
function Hud:draw(player)
    if not player or not self.health then return end
    local Theme = UI.Theme
    local px, c = Theme.px, Theme.colors
    local rowH, gap = px(Bar.ICON_SIZE), px(ROW_GAP)
    local x = px(MARGIN)
    local y = love.graphics.getHeight() - px(MARGIN) - rowH * 2 - gap

    local bx, by, bh = Bar.draw(self.health, "heart", x, y, HEALTH_H, c.danger)
    local font = Theme.font("small")
    UI.Label.draw{ text = ("%d / %d"):format(math.ceil(player.health), player.maxHealth),
        x = bx, y = Theme.centerY(by, bh, font), width = px(Bar.WIDTH) - px(TEXT_PAD),
        align = "right", font = font, shadow = true }

    -- grey while exhausted: no sprinting until it refills
    Bar.draw(self.stamina, "stamina", x, y + rowH + gap, STAMINA_H,
        player.stamina.exhausted and c.textDim or c.warning)
    love.graphics.setColor(1, 1, 1, 1)
end

return Hud
