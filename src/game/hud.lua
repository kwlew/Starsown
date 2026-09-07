--- The in-play HUD, bottom-left: a health bar, the coin count, and the
-- combat level. Screen space, so it draws after the camera detaches (see
-- Play:draw) and every literal here is design-space px through Theme.px.
--
-- Colours are Theme roles, since this is chrome -- with one deliberate
-- exception. The health fill reads from game/palette.lua, the same red every
-- enemy's health bar already uses: under a themed palette like "ruby",
-- Theme.colors.danger would put a red bar on a red-tinted panel and stop
-- reading as health at all, which is the whole reason palette.lua is kept
-- separate from the theme.

local Theme = require "ui.core.theme"
local Palette = require "game.palette"
local Label = require "ui.text.label"
local Skills = require "game.skills"
local I18n = require "core.i18n"
local Format = require "utils.format"
local Math = require "utils.math"

local Hud = {}

local PAD = 18       -- from the window edge
local BAR_W = 190
local BAR_H = 16
local ROW_GAP = 6    -- between the stacked text rows
local BAR_TEXT_GAP = 10 -- between the bar and the "7 / 10" beside it
local BORDER = 2
local HP_DAMP_RATE = 10 -- higher converges faster; see Math.damp

--- the bar's own eased position, independent of the real hp it's chasing --
-- nil until the first update() so the very first draw snaps rather than
-- animating up from a meaningless zero
local displayedHp = nil

--- squared off rather than rounded, matching the health bars already drawn
-- over enemies -- one health bar shouldn't read differently from another
---@param x number
---@param y number
---@param w number
---@param h number
---@param fraction number # 0..1
local function drawBar(x, y, w, h, fraction)
    love.graphics.setColor(Palette.healthTrack)
    love.graphics.rectangle("fill", x, y, w, h)

    if fraction > 0 then
        love.graphics.setColor(Palette.health)
        love.graphics.rectangle("fill", x, y, w * fraction, h)
    end

    love.graphics.setLineWidth(Theme.px(BORDER))
    Theme.setColor(Theme.colors.panelBorder)
    love.graphics.rectangle("line", x, y, w, h)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

--- eases the drawn bar toward the real hp instead of snapping to it, so a
-- hit -- or a respawn's heal back to full -- reads as a change rather than a
-- teleport. Only the bar eases; draw()'s "7 / 10" text stays exact, since a
-- number lagging behind the real value is confusing rather than pleasant.
---@param dt number
---@param player table # reads hp
function Hud.update(dt, player)
    local hp = math.max(0, player.hp)
    displayedHp = displayedHp and Math.damp(displayedHp, hp, HP_DAMP_RATE, dt) or hp
end

--- drops the eased value, so a brand new run's first update() snaps
-- straight to its starting hp instead of animating up from whatever the
-- previous run last left behind
function Hud.reset()
    displayedHp = nil
end

--- health, coins and combat level. Everything is read, never written, so a
-- caller can hand over its live tables directly.
---@param player table # reads hp/maxHp
---@param currency number|nil
---@param skills table|nil # save.skills, for the level readout
function Hud.draw(player, currency, skills)
    local colors = Theme.colors
    local font = Theme.font("small")
    local pad = Theme.px(PAD)
    local barW, barH = Theme.px(BAR_W), Theme.px(BAR_H)
    local gap, lineH = Theme.px(ROW_GAP), font:getHeight()

    local x = pad
    local barY = love.graphics.getHeight() - pad - barH
    local coinsY = barY - gap - lineH
    local levelY = coinsY - gap - lineH

    Label.draw{
        text = I18n.t("game.hud.level", {
            skill = Skills.name("combat"),
            n = Skills.levelOf(skills, "combat"),
        }),
        x = x, y = levelY, width = barW, align = "left",
        font = font, color = colors.textDim, shadow = true,
    }

    Label.draw{
        text = I18n.t("game.hud.coins", { n = Format.number(currency or 0) }),
        x = x, y = coinsY, width = barW, align = "left",
        font = font, color = colors.textMuted, shadow = true,
    }

    -- hp can sit below zero for the frame between a killing blow and
    -- Play:onPlayerDeath, so both the bar and the readout floor it. The bar
    -- itself draws from the eased displayedHp (update()'s job to keep
    -- current), not this frame's real hp -- falling back to hp if update()
    -- was never called, so draw() alone never divides by a stale nil.
    local hp = math.max(0, player.hp)
    local maxHp = player.maxHp
    local shown = displayedHp or hp
    drawBar(x, barY, barW, barH, maxHp > 0 and Math.clamp01(shown / maxHp) or 0)

    Label.draw{
        text = ("%d / %d"):format(hp, maxHp),
        x = x + barW + Theme.px(BAR_TEXT_GAP),
        y = barY + (barH - lineH) / 2,
        align = "left",
        font = font, color = colors.text, shadow = true,
    }
end

return Hud
