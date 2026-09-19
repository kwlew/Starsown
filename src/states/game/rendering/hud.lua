-- src/states/game/rendering/hud.lua
-- Bottom-of-screen status bar: player HP as a number (the bar over the player
-- already shows it as a gauge), plus placeholders for stamina and currency.

local Theme = require "ui.core.theme"
local Math = require "utils.math"
local I18n = require "core.i18n"
local Palette = require "states.game.rendering.palette"

local Hud = {}

local HEIGHT = 40
local PAD = 20
local GAP = 14
local SECTION_GAP = 32
local BAR_H = 8
local STAMINA_W = 200
local RED_FROM = 0.7 -- HP ratio where the number starts shifting red; fully red at 0
local PANEL_ALPHA = 0.72
local EXHAUSTED_ALPHA = 0.45

---@return number # the bar's height in pixels
function Hud.height()
    return Theme.px(HEIGHT)
end

--- vertical divider between sections
local function drawDivider(x, centerY, span)
    Theme.setColor(Theme.colors.panelBorder, 0.7)
    love.graphics.line(x + 0.5, centerY - span / 2, x + 0.5, centerY + span / 2)
end

--- Screen-space; call outside the camera transform.
---@param player table
function Hud.draw(player)
    local px = Theme.px
    local screenW, screenH = love.graphics.getDimensions()
    local h = px(HEIGHT)
    local y = screenH - h
    local centerY = y + h / 2
    local pad, gap, sectionGap = px(PAD), px(GAP), px(SECTION_GAP)

    Theme.setColor(Theme.colors.panel, PANEL_ALPHA)
    love.graphics.rectangle("fill", 0, y, screenW, h)
    Theme.setColor(Theme.colors.panelBorder, 0.8)
    love.graphics.line(0, y + 0.5, screenW, y + 0.5)

    local small, value = Theme.font("small"), Theme.font("help")
    local x = pad

    -- HP: "HP  8 / 10", the number blending toward red as HP falls
    local ratio = math.min(1, player.hpFront / player.maxHp)
    local redness = Math.clamp01((RED_FROM - ratio) / RED_FROM)
    local r, g, b = Theme.lerp(Theme.colors.text, Palette.hud.hp, redness)

    Theme.pushFont(small)
    love.graphics.setColor(Palette.hud.hp)
    love.graphics.print(I18n.t("hud.hp"), x, centerY - small:getHeight() / 2)
    x = x + small:getWidth(I18n.t("hud.hp")) + gap
    Theme.popFont()

    local current = tostring(math.ceil(player.hp))
    local total = " / " .. player.maxHp
    Theme.pushFont(value)
    love.graphics.setColor(r, g, b)
    love.graphics.print(current, x, centerY - value:getHeight() / 2)
    x = x + value:getWidth(current)
    Theme.setColor(Theme.colors.textDim)
    love.graphics.print(total, x, centerY - value:getHeight() / 2)
    x = x + value:getWidth(total) + sectionGap
    Theme.popFont()

    drawDivider(x, centerY, h * 0.5)
    x = x + sectionGap

    -- stamina: eased fill over a white trail, dimmed while exhausted
    Theme.pushFont(small)
    love.graphics.setColor(Palette.hud.stamina)
    love.graphics.print(I18n.t("hud.stamina"), x, centerY - small:getHeight() / 2)
    x = x + small:getWidth(I18n.t("hud.stamina")) + gap

    local barW, barH = px(STAMINA_W), px(BAR_H)
    Theme.setColor(Theme.colors.panelBorder, 0.6)
    love.graphics.rectangle("fill", x, centerY - barH / 2, barW, barH, barH / 2)
    local top = centerY - barH / 2
    local front = barW * Math.clamp01(player.staminaFront / player.maxStamina)
    local trail = barW * Math.clamp01(player.staminaTrail / player.maxStamina)
    local alpha = 1 - (1 - EXHAUSTED_ALPHA) * player.exhaustFade

    if trail > front + 0.5 then
        local color = Palette.hud.staminaTrail
        love.graphics.setColor(color[1], color[2], color[3], alpha)
        love.graphics.rectangle("fill", x, top, math.max(trail, barH), barH, barH / 2)
    end
    if front > 0 then
        local color = Palette.hud.stamina
        love.graphics.setColor(color[1], color[2], color[3], alpha)
        love.graphics.rectangle("fill", x, top, math.max(front, barH), barH, barH / 2)
    end

    love.graphics.setColor(Palette.hud.currency)
    love.graphics.printf(I18n.t("hud.currency") .. "  --", 0, centerY - small:getHeight() / 2,
        screenW - pad, "right")
    Theme.popFont()

    love.graphics.setColor(1, 1, 1, 1)
end

return Hud
