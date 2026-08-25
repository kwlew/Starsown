local StateManager = require "core.stateManager"
local UI = require "ui"
local I18n = require "core.i18n"
local Format = require "utils.format"
local StatsService = require "services.stats"
local Presence = require "services.presence"
local Globals = require "globals"
local TextFactory = require "ui.text.textFactory"

local HEADING_Y_RATIO = 0.12
local LIST_Y_RATIO = 0.30
local ROW_H      = 34
local LIST_MAX_W = 420
local BACK_W     = 180
local STATUS_MAX_W = 460

local Stats = {}

local ROWS = {
    { labelKey = "stats.online",  get = function() return StatsService.online end },
    { labelKey = "stats.total",   get = function() return StatsService.stars end },
    { labelKey = "stats.golden",  get = function() return StatsService.golden end,
      tone = "gold" },
    { labelKey = "stats.rainbow", get = function() return StatsService.rainbow end,
      tone = "rainbow" },
}

local CHROMA_SPAN = 90
local CHROMA_SPEED = 0.8

local CHROMA_ROW
for i, row in ipairs(ROWS) do
    if row.tone == "rainbow" then CHROMA_ROW = i end
end

local function valueText(n)
    if not n then return I18n.t("stats.unavailable") end
    return Format.group(n)
end

function Stats:syncChroma()
    local row = self.rows and self.rows[CHROMA_ROW]
    if not row then return end

    local font = UI.Theme.font("body")
    local text = valueText(ROWS[CHROMA_ROW].get())

    if not self.chroma or self.chroma.font ~= font then
        self.chroma = TextFactory:new{
            text = text,
            font = font,
            limit = row.w,
            align = "right",
            speed = CHROMA_SPEED,
            scale = UI.Theme.px(CHROMA_SPAN),
        }
    elseif self.chroma.text ~= text or self.chroma.limit ~= row.w then
        self.chroma.limit = row.w
        self.chroma.scale = UI.Theme.px(CHROMA_SPAN)
        self.chroma:setText(text)
    end
end

function Stats:enter(previousName, opts)
    Presence.set{
        details = "Stats",
        state = "Viewing stats",
        smallText = "Stats",
        startedAt = Globals.game.startedAt,
    }
    self.returnTo = StateManager.returnTarget(previousName, opts, "stats")

    self.mouseX, self.mouseY = love.mouse.getPosition()

    if not self.group then
        self.group = UI.FocusGroup.new()
        self.group.onFocusChanged = UI.Sfx.focus
    end

    if not self.backButton then
        self.backButton = UI.Button.new{
            label = function() return I18n.t("stats.back") end,
            onSelect = function() self:leave() end,
        }
        self.group:setWidgets{ self.backButton }
    end

    self:layout()
end

function Stats:leave()
    UI.Sfx.select()
    StateManager.fadeTo(self.returnTo)
end

function Stats:layout()
    local w, h = love.graphics.getDimensions()
    local m = UI.Theme.metrics

    local listW = math.min(UI.Theme.px(LIST_MAX_W), w * 0.6)
    local listX = (w - listW) / 2
    local rowH = UI.Theme.px(ROW_H)

    local listH = #ROWS * rowH
    local backW = math.min(UI.Theme.px(BACK_W), listW)

    local top = h * HEADING_Y_RATIO + UI.Theme.font("heading"):getHeight() + m.rowGap
    local blockH = listH + m.rowGap + m.rowHeight
    local listY = math.max(top, math.min(h * LIST_Y_RATIO, UI.Label.hintY() - m.rowGap - blockH))

    self.rows = self.rows or {}
    for i = 1, #ROWS do
        self.rows[i] = { x = listX, y = listY + (i - 1) * rowH, w = listW, h = rowH }
    end

    self.backButton:setBounds((w - backW) / 2, listY + listH + m.rowGap, backW, m.rowHeight)

    self:syncChroma()
end

function Stats:resize()
    self:layout()
end

function Stats:update(dt)
    self.group:update(dt)

    self:syncChroma()
    if self.chroma then
        self.chroma.speed = UI.Motion.reduced and 0 or CHROMA_SPEED
        self.chroma:update(dt)
    end
end

function Stats:keypressed(key)
    if key == "escape" then
        self:leave()
        return
    end
    self.group:keypressed(key)
end

function Stats:mousepressed(x, y, button)  self.group:mousepressed(x, y, button)  end
function Stats:mousereleased(x, y, button) self.group:mousereleased(x, y, button) end

function Stats:mousemoved(x, y)
    self.mouseX, self.mouseY = x, y
    self.group:mousemoved(x, y)
end

function Stats:statusKey()
    for _, row in ipairs(ROWS) do
        if row.get() ~= nil then return nil end
    end
    return StatsService.enabled and "stats.waiting" or "stats.sharingOff"
end

function Stats:valueColor(tone)
    if tone == "gold" then return UI.Theme.fixedColors.gold end
    return UI.Theme.colors.accent
end

function Stats:drawChromaValue(y)
    local row = self.rows[CHROMA_ROW]
    local offset = UI.Label.shadowOffset()

    self.chroma:setPosition(row.x, y)
    UI.Theme.setColor(UI.Theme.colors.shadow)
    love.graphics.draw(self.chroma.textObject, row.x + offset, y + offset)
    love.graphics.setColor(1, 1, 1, 1)

    self.chroma:drawChroma()
end

function Stats:draw()
    local h = love.graphics.getHeight()

    UI.Label.draw{
        text = I18n.t("stats.title"),
        y = h * HEADING_Y_RATIO,
        font = UI.Theme.font("heading"),
        shadow = true,
    }

    local labelFont = UI.Theme.font("small")
    local valueFont = UI.Theme.font("body")
    local hairline = math.max(1, UI.Theme.px(1))

    for i, row in ipairs(self.rows) do
        if i > 1 then
            UI.Theme.setColor(UI.Theme.colors.panelBorder, 0.5)
            love.graphics.rectangle("fill", row.x, row.y, row.w, hairline)
        end

        UI.Label.draw{
            text = I18n.t(ROWS[i].labelKey),
            x = row.x, y = UI.Theme.centerY(row.y, row.h, labelFont),
            width = row.w, align = "left",
            font = labelFont,
            color = UI.Theme.colors.textMuted,
            shadow = true,
        }

        local value = ROWS[i].get()
        local valueY = UI.Theme.centerY(row.y, row.h, valueFont)

        if ROWS[i].tone == "rainbow" and value and self.chroma then
            self:drawChromaValue(valueY)
        else
            UI.Label.draw{
                text = valueText(value),
                x = row.x, y = valueY,
                width = row.w, align = "right",
                font = valueFont,
                color = value and self:valueColor(ROWS[i].tone) or UI.Theme.colors.textDim,
                shadow = true,
            }
        end
    end

    self.backButton:draw()

    local statusKey = self:statusKey()
    if statusKey then
        local w = love.graphics.getWidth()
        local noteW = math.min(w * 0.7, UI.Theme.px(STATUS_MAX_W))
        UI.Label.draw{
            text = I18n.t(statusKey),
            x = (w - noteW) / 2,
            y = self.backButton.y + self.backButton.h + UI.Theme.metrics.rowGap * 2,
            width = noteW,
            font = UI.Theme.font("small"),
            color = UI.Theme.colors.textDim,
            shadow = true,
        }
    end

    UI.Label.hint(I18n.t("stats.hint"))

    local overWidget, dangerous = self.group:hovering(self.mouseX or -1, self.mouseY or -1)
    UI.Cursor.setHover(self.mouseX ~= nil and overWidget, dangerous)
end

return Stats
