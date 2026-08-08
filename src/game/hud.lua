-- src/game/hud.lua
-- The run's interface: the status strip along the top, the build/action bar
-- along the bottom, and the panel that appears when a tower is selected.
--
--   local hud = Hud.new(game)      -- `game` is the owning state
--   hud:layout(w, h)               -- also decides how much room the board gets
--   hud:update(dt)
--   hud:mousepressed(x, y, b)      -- true if the HUD consumed the click
--   hud:draw()
--
-- The HUD holds no state of its own beyond its geometry. It reads the world and
-- the state's current selection every frame and calls back into the state to
-- act, the same way achievements.lua's TreePane hands everything to its owner.
-- That means there is no second copy of "which tower is selected" to fall out of
-- sync with the one the board is drawing.

local UI = require "lib.ui"
local I18n = require "lib.i18n"
local Format = require "lib.utils.format"
local Config = require "game.config"

local Hud = {}
Hud.__index = Hud

-- Design-space px (see Theme.px).
local MARGIN     = 16
local TOP_H      = 56
local BAR_H      = 78
local TILE_W     = 150 -- a tower entry in the build bar
local ACTION_W   = 190 -- Call Wave / Overcharge, whose labels are the longest
local BAR_GAP    = 10
local PANEL_W    = 300 -- the selected-tower panel
local PANEL_PAD  = 14
local CHIP_GAP   = 22  -- between the gold and lives readouts
local PROGRESS_H = 10
local PROGRESS_W = 340 -- cap: a wave timer stretched across a 1080p strip reads
                       -- as a divider rather than as a bar that is filling

--------------------------------------------------------------------------------
-- A bar entry
--
-- One widget class covers both halves of the bar: a tower to build and an
-- action to take differ only in what they compute for their subtitle and their
-- enabled state, both of which are already callbacks.
--------------------------------------------------------------------------------

local BarButton = {}
UI.Widget.extend(BarButton)

function BarButton.new(config)
    local self = UI.Widget.new(BarButton, config)
    self.icon = config.icon
    self.hotkey = config.hotkey
    self.subtitle = config.subtitle   -- function -> string
    -- Colour of the value line while the entry is live. Deliberately NOT the
    -- accent: Carbon's accent is darker than textDim, so an affordable price
    -- drawn in it would read as more greyed-out than an unaffordable one. Gold
    -- figures take `warning` (which every palette keeps legible and which the
    -- coin readout already uses); anything else takes plain text.
    self.valueColor = config.valueColor
    self.isSelected = config.isSelected -- function -> boolean
    self.isEnabled = config.isEnabled   -- function -> boolean
    self.onSelect = config.onSelect
    self.chosen = false
    return self
end

-- A chosen entry stays lit whether or not the cursor is on it: "this is the
-- tower I am placing" has to survive moving the mouse to the board.
function BarButton:isLit()
    return self.focused or self.chosen
end

-- Both flags are recomputed every frame rather than pushed on change: they
-- depend on gold, which moves continuously.
function BarButton:update(dt)
    if self.isEnabled then self.enabled = self.isEnabled() end
    self.chosen = self.isSelected ~= nil and self.isSelected() or false
    UI.Widget.update(self, dt)
end

function BarButton:activate()
    if not self:isInteractive() then return end
    if self.onSelect then self.onSelect(self) end
end

-- Name small on top, number large underneath. The inverted hierarchy is
-- deliberate: the name of a button never changes and is read once, while the
-- figure under it (a price, a payout, a countdown) is the thing being checked
-- every few seconds. It also keeps the long words — "Overcharge", "Cannon" —
-- in the narrow font, which is what lets them fit the row without wrapping.
function BarButton:draw()
    local c, m = UI.Theme.colors, UI.Theme.metrics
    local alpha = self:alpha()
    self:drawRow(alpha)

    local nameFont = UI.Theme.font("small")
    local valueFont = UI.Theme.font("button")

    local iconSize = self.h * 0.40
    local iconX = self.x + m.padding
    UI.Theme.setColor(self.chosen and c.accent or c.text, alpha)
    UI.Glyph.draw(self.icon, iconX, self.y + (self.h - iconSize) / 2, iconSize)

    -- The hotkey badge sits in the top-right corner, so the text column stops
    -- short of it rather than wrapping underneath it.
    local hotkeyW = 0
    if self.hotkey then
        hotkeyW = nameFont:getWidth(self.hotkey) + UI.Theme.px(6)
    end

    local textX = iconX + iconSize + UI.Theme.px(10)
    local textW = math.max(0, self.x + self.w - m.padding - textX - hotkeyW)
    local y = self.y + (self.h - nameFont:getHeight() - valueFont:getHeight()) / 2

    UI.Theme.pushFont(nameFont)
    UI.Theme.setColor(c.textMuted, alpha)
    love.graphics.printf(self:labelText(), textX, y, textW, "left")

    if self.hotkey then
        UI.Theme.setColor(c.textDim, alpha * 0.9)
        love.graphics.printf(self.hotkey, self.x, y,
            self.w - UI.Theme.px(8), "right")
    end
    UI.Theme.popFont()

    UI.Theme.pushFont(valueFont)
    -- Full colour while the entry is live, dim the moment it isn't affordable
    -- or ready — so affordability reads off the number itself, not just the row.
    UI.Theme.setColor(self.enabled and (self.valueColor or c.text) or c.textDim, alpha)
    love.graphics.printf(self.subtitle and self.subtitle() or "", textX,
        y + nameFont:getHeight(), self.x + self.w - m.padding - textX, "left")
    UI.Theme.popFont()

    love.graphics.setColor(1, 1, 1, 1)
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function Hud.new(owner)
    local self = setmetatable({ owner = owner, buttons = {} }, Hud)

    -- Every closure below reaches through `owner` for the world rather than
    -- capturing it, so starting a new run doesn't leave the bar reporting the
    -- old one's gold.
    local function world() return owner.world end

    -- One entry per tower type, straight from the config: adding a tower type
    -- adds a build button with no change here.
    for index, def in ipairs(Config.towers) do
        self.buttons[#self.buttons + 1] = BarButton.new{
            icon = def.icon,
            hotkey = tostring(index),
            label = function() return I18n.t("game.tower." .. def.id) end,
            subtitle = function() return Format.number(def.cost) end,
            valueColor = UI.Theme.colors.warning,
            isSelected = function() return owner.buildType == def.id end,
            isEnabled = function() return world().gold >= def.cost end,
            onSelect = function() owner:selectBuild(def.id) end,
        }
    end
    self.towerButtonCount = #self.buttons

    self.callButton = BarButton.new{
        icon = "wave",
        -- Key names stay untranslated, like the "1"/"2"/"E" badges beside them:
        -- the badge names a physical key, and the key doesn't move per locale.
        hotkey = "SPACE",
        label = function() return I18n.t("game.callWave") end,
        -- The payout is the whole argument for pressing this, so it is the
        -- subtitle rather than a tooltip.
        subtitle = function()
            if world().phase ~= "intermission" then return I18n.t("game.inProgress") end
            return "+" .. Format.number(world():callBonus())
        end,
        valueColor = UI.Theme.colors.warning,
        isEnabled = function() return world().phase == "intermission" end,
        onSelect = function() owner:callWave() end,
    }

    self.overchargeButton = BarButton.new{
        icon = "flame",
        hotkey = "E",
        label = function() return I18n.t("game.overcharge") end,
        subtitle = function()
            local o = world().overcharge
            if o.active > 0 then
                return I18n.t("game.overchargeActive", { n = Format.countdown(o.active) })
            end
            if o.cooldown > 0 then
                return Format.duration(o.cooldown)
            end
            return I18n.t("game.ready")
        end,
        isSelected = function() return world().overcharge.active > 0 end,
        isEnabled = function() return world():canOvercharge() end,
        onSelect = function() owner:overcharge() end,
    }

    self.buttons[#self.buttons + 1] = self.callButton
    self.buttons[#self.buttons + 1] = self.overchargeButton

    -- The selected-tower panel's controls. Their labels carry live prices, so
    -- they are functions like every other label in this codebase.
    self.upgradeButton = UI.Button.new{
        font = "small",
        label = function()
            local tower = owner.selected
            if not tower then return "" end
            local cost = world():upgradeCost(tower)
            if not cost then return I18n.t("game.maxLevel") end
            return I18n.t("game.upgradeFor", { n = Format.number(cost) })
        end,
        onSelect = function() owner:upgradeSelected() end,
    }

    self.sellButton = UI.Button.new{
        font = "small",
        danger = true,
        label = function()
            local tower = owner.selected
            if not tower then return "" end
            return I18n.t("game.sellFor", { n = Format.number(world():sellValue(tower)) })
        end,
        onSelect = function() owner:sellSelected() end,
    }

    self.progress = UI.ProgressBar.new{ showPercent = false, fillSpeed = 10 }

    return self
end

--------------------------------------------------------------------------------
-- Layout
--
-- Computes every rect the HUD owns and, as a side effect, the rect left over
-- for the board. Called from the state's enter and resize, never from draw.
--------------------------------------------------------------------------------

function Hud:layout(w, h)
    local pad = UI.Theme.px(MARGIN)
    local topH = UI.Theme.px(TOP_H)
    local barH = UI.Theme.px(BAR_H)

    self.top = { x = pad, y = pad, w = w - pad * 2, h = topH }
    self.bar = { x = pad, y = h - pad - barH, w = w - pad * 2, h = barH }

    -- Whatever is left between the two strips. The board is centered inside it
    -- by the renderer, which knows its own aspect ratio.
    local boardTop = self.top.y + topH + pad
    self.boardArea = {
        x = pad, y = boardTop,
        w = w - pad * 2,
        h = math.max(UI.Theme.px(120), self.bar.y - pad - boardTop),
    }

    -- Build entries run from the left, actions are pinned to the right, and the
    -- gap between them absorbs the window width.
    local tileW = UI.Theme.px(TILE_W)
    local actionW = UI.Theme.px(ACTION_W)
    local gap = UI.Theme.px(BAR_GAP)
    local innerH = barH - gap * 2

    -- At the narrowest supported window the bar would otherwise run off both
    -- ends, or the build tiles would slide under the actions. Everything shrinks
    -- by the same factor instead, so the bar stays one row at any resolution.
    local needed = tileW * self.towerButtonCount + actionW * 2
        + gap * (self.towerButtonCount + 1)
    if needed > self.bar.w then
        local squeeze = self.bar.w / needed
        tileW = math.floor(tileW * squeeze)
        actionW = math.floor(actionW * squeeze)
    end

    for i = 1, self.towerButtonCount do
        self.buttons[i]:setBounds(self.bar.x + (i - 1) * (tileW + gap),
            self.bar.y + gap, tileW, innerH)
    end

    local right = self.bar.x + self.bar.w
    self.overchargeButton:setBounds(right - actionW, self.bar.y + gap, actionW, innerH)
    self.callButton:setBounds(right - actionW * 2 - gap, self.bar.y + gap, actionW, innerH)

    -- The tower panel floats over the bottom-right of the board. It only exists
    -- while something is selected, so nothing else is laid out around it.
    local panelW = UI.Theme.px(PANEL_W)
    local panelPad = UI.Theme.px(PANEL_PAD)
    local rowH = UI.Theme.px(34)
    local panelH = panelPad * 2 + UI.Theme.font("button"):getHeight()
        + UI.Theme.font("small"):getHeight() * 3 + UI.Theme.px(12) + rowH

    self.panel = {
        x = right - panelW,
        y = self.bar.y - pad - panelH,
        w = panelW, h = panelH,
    }

    local buttonW = (panelW - panelPad * 2 - gap) / 2
    local buttonY = self.panel.y + panelH - panelPad - rowH
    self.upgradeButton:setBounds(self.panel.x + panelPad, buttonY, buttonW, rowH)
    self.sellButton:setBounds(self.panel.x + panelPad + buttonW + gap, buttonY, buttonW, rowH)

    return self.boardArea
end

--------------------------------------------------------------------------------
-- Input
--
-- Every handler answers "did the HUD take this?", so the state can offer the
-- event to the board only when the HUD didn't want it.
--------------------------------------------------------------------------------

function Hud:panelVisible()
    return self.owner.selected ~= nil
end

function Hud:contains(x, y)
    if UI.Theme.pointIn(x, y, self.bar.x, self.bar.y, self.bar.w, self.bar.h) then
        return true
    end
    if UI.Theme.pointIn(x, y, self.top.x, self.top.y, self.top.w, self.top.h) then
        return true
    end
    local p = self.panel
    return self:panelVisible() and UI.Theme.pointIn(x, y, p.x, p.y, p.w, p.h)
end

function Hud:panelButtons()
    return self.upgradeButton, self.sellButton
end

function Hud:mousemoved(x, y)
    for _, button in ipairs(self.buttons) do
        button.focused = button:contains(x, y)
    end
    if self:panelVisible() then
        self.upgradeButton.focused = self.upgradeButton:contains(x, y)
        self.sellButton.focused = self.sellButton:contains(x, y)
    else
        self.upgradeButton.focused = false
        self.sellButton.focused = false
    end
end

function Hud:mousepressed(x, y, mouseButton)
    if mouseButton ~= 1 then return false end

    if self:panelVisible() then
        for _, button in ipairs({ self.upgradeButton, self.sellButton }) do
            if button.enabled and button:contains(x, y) then
                button:activate()
                return true
            end
        end
    end

    for _, button in ipairs(self.buttons) do
        if button:contains(x, y) then
            -- Consumed either way: a click that lands on a greyed-out entry
            -- must not fall through and build something on the board behind it.
            if button.enabled then button:activate() end
            return true
        end
    end

    -- Anywhere else on the HUD's own furniture still counts as handled.
    return self:contains(x, y)
end

function Hud:hovering(x, y)
    for _, button in ipairs(self.buttons) do
        if button.enabled and button:contains(x, y) then return true end
    end
    if self:panelVisible() then
        if self.upgradeButton.enabled and self.upgradeButton:contains(x, y) then return true end
        if self.sellButton.enabled and self.sellButton:contains(x, y) then return true end
    end
    return false
end

function Hud:update(dt)
    local world = self.owner.world

    for _, button in ipairs(self.buttons) do
        button:update(dt)
    end

    -- Only meaningful while the panel is up, but kept ticking regardless so its
    -- glow doesn't snap on when the panel reappears.
    local tower = self.owner.selected
    self.upgradeButton.enabled = tower ~= nil
        and world:upgradeCost(tower) ~= nil
        and world.gold >= (world:upgradeCost(tower) or math.huge)
    self.sellButton.enabled = tower ~= nil
    self.upgradeButton:update(dt)
    self.sellButton:update(dt)

    self.progress:setProgress(world:waveProgress())
    self.progress:update(dt)
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

-- The one-line description of what the wave schedule is doing right now.
function Hud:phaseText()
    local world = self.owner.world
    if world.phase == "intermission" then
        return I18n.t("game.nextWave", { n = Format.countdown(world.phaseTimer) })
    end
    if world.phase == "spawning" then
        local key = world.bossWave and "game.bossIncoming" or "game.incoming"
        return I18n.t(key)
    end
    return I18n.t("game.clearing")
end

-- An icon and a number, drawn right-to-left from `right`. Returns the x it
-- ended at, so the next chip can be placed beside it without either of them
-- knowing how wide the other turned out to be.
function Hud:drawChip(icon, text, color, right, centerY)
    local font = UI.Theme.font("button")
    local iconSize = font:getHeight() * 0.9
    local textW = font:getWidth(text)

    local x = right - textW
    UI.Theme.pushFont(font)
    UI.Theme.setColor(UI.Theme.colors.text)
    love.graphics.print(text, x, centerY - font:getHeight() / 2)
    UI.Theme.popFont()

    x = x - UI.Theme.px(8) - iconSize
    UI.Theme.setColor(color)
    UI.Glyph.draw(icon, x, centerY - iconSize / 2, iconSize)

    return x
end

function Hud:drawTop()
    local world = self.owner.world
    local c, m = UI.Theme.colors, UI.Theme.metrics
    local top = self.top

    UI.Theme.panel(top.x, top.y, top.w, top.h)

    local centerY = top.y + top.h / 2
    local titleFont = UI.Theme.font("button")
    local smallFont = UI.Theme.font("small")

    -- Wave number, left.
    local waveText = I18n.t("game.wave", { n = world.wave })
    UI.Theme.pushFont(titleFont)
    UI.Theme.setColor(c.text)
    love.graphics.print(waveText, top.x + m.padding, centerY - titleFont:getHeight() / 2)
    local waveW = titleFont:getWidth(waveText)
    UI.Theme.popFont()

    -- Best wave, just after it and dimmed: the number an idle run is actually
    -- chasing, and the one a setback leaves standing.
    if world.bestWave > world.wave then
        UI.Theme.pushFont(smallFont)
        UI.Theme.setColor(c.textDim)
        love.graphics.print(I18n.t("game.best", { n = world.bestWave }),
            top.x + m.padding + waveW + UI.Theme.px(10),
            centerY - smallFont:getHeight() / 2)
        UI.Theme.popFont()
    end

    -- Lives and gold, right. Lives goes furthest right so the two never swap
    -- places as the gold figure grows and shrinks.
    local livesColor = world.lives <= 5 and c.danger or c.text
    local livesX = self:drawChip("shield", tostring(world.lives), livesColor,
        top.x + top.w - m.padding, centerY)
    local goldX = self:drawChip("coin", Format.number(world.gold), c.warning,
        livesX - UI.Theme.px(CHIP_GAP), centerY)

    -- The progress bar sits in the space between the wave label and the chips,
    -- capped and centered in it rather than filling it. Skipped entirely when
    -- the window is too narrow for it to say anything.
    local spanX = top.x + m.padding + waveW + UI.Theme.px(120)
    local spanW = goldX - UI.Theme.px(CHIP_GAP) - spanX
    if spanW < UI.Theme.px(80) then return end

    local barW = math.min(spanW, UI.Theme.px(PROGRESS_W))
    local barX = spanX + (spanW - barW) / 2
    local barH = UI.Theme.px(PROGRESS_H)
    UI.Theme.pushFont(smallFont)
    UI.Theme.setColor(c.textMuted)
    love.graphics.printf(self:phaseText(), barX,
        centerY - smallFont:getHeight() - UI.Theme.px(1), barW, "center")
    UI.Theme.popFont()

    self.progress:draw(barX, centerY + UI.Theme.px(3), barW, barH)
end

function Hud:drawPanel()
    local tower = self.owner.selected
    if not tower then return end

    local world = self.owner.world
    local c = UI.Theme.colors
    local p = self.panel
    local pad = UI.Theme.px(PANEL_PAD)
    local def = Config.towerById[tower.type]

    UI.Theme.panel(p.x, p.y, p.w, p.h)

    local titleFont = UI.Theme.font("button")
    local smallFont = UI.Theme.font("small")
    local x, w = p.x + pad, p.w - pad * 2
    local y = p.y + pad

    -- Icon and name on one line, with the level as the value on the right —
    -- the same label-left / value-right shape every settings row in the game
    -- uses, so it reads as familiar furniture.
    local iconSize = titleFont:getHeight()
    UI.Theme.setColor(c.accent)
    UI.Glyph.draw(def.icon, x, y, iconSize)

    UI.Theme.pushFont(titleFont)
    UI.Theme.setColor(c.text)
    love.graphics.print(I18n.t("game.tower." .. def.id), x + iconSize + UI.Theme.px(8), y)
    UI.Theme.setColor(c.warning)
    love.graphics.printf(I18n.t("game.level", { n = tower.level }), x, y, w, "right")
    UI.Theme.popFont()

    y = y + titleFont:getHeight() + UI.Theme.px(6)

    -- Two stat lines, label left and value right.
    UI.Theme.pushFont(smallFont)
    local rows = {
        { I18n.t("game.dps"), string.format("%.1f", world:towerDps(tower)) },
        { I18n.t("game.range"), string.format("%.1f", tower.range) },
        { I18n.t("game.kills"), Format.number(tower.kills) },
    }
    for _, row in ipairs(rows) do
        UI.Theme.setColor(c.textDim)
        love.graphics.print(row[1], x, y)
        UI.Theme.setColor(c.textMuted)
        love.graphics.printf(row[2], x, y, w, "right")
        y = y + smallFont:getHeight()
    end
    UI.Theme.popFont()

    self.upgradeButton:draw()
    self.sellButton:draw()
end

function Hud:draw()
    self:drawTop()
    for _, button in ipairs(self.buttons) do
        button:draw()
    end
    self:drawPanel()
    love.graphics.setColor(1, 1, 1, 1)
end

return Hud
