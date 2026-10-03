--- The four world-stat rows, in a bordered card.

local I18n = require("core.i18n")
local StatsService = require("services.stats")
local UI = require("ui")

local Readout = {}
Readout.__index = Readout

local ROW_H = 44
local MAX_W = 480
local WIDTH_RATIO = 0.6
local CHROMA_SPAN = 160 -- px per rainbow cycle
local CHROMA_SPEED = 0.5
local STRIPE_W = 4     -- the coloured kind marker
local STRIPE_INSET = 8
local LABEL_GAP = 14

local ROWS = {
    { key = "stats.online", get = function() return StatsService.online end, tone = "accent" },
    { key = "stats.total", get = function() return StatsService.stars end, tone = "text" },
    { key = "stats.golden", get = function() return StatsService.golden end, tone = "gold" },
    { key = "stats.rainbow", get = function() return StatsService.rainbow end, tone = "rainbow" },
}

---@param n number|nil
---@return string
local function valueText(n)
    return n and I18n.number(n) or I18n.t("stats.unavailable")
end

---@return table
function Readout.new()
    local self = setmetatable({ rows = {}, chroma = nil }, Readout)
    for i, spec in ipairs(ROWS) do
        self.rows[i] = { spec = spec, introAlpha = 1, x = 0, y = 0, w = 0, h = 0 }
    end
    return self
end

---@return number w
---@return number h # the card's size
function Readout:size()
    local w = love.graphics.getWidth()
    local pad = UI.Theme.metrics.padding
    local listW = math.min(UI.Theme.px(MAX_W), w * WIDTH_RATIO)
    return listW + pad * 2, #ROWS * UI.Theme.px(ROW_H) + pad * 2
end

---@param x number # card top-left
---@param y number
function Readout:layout(x, y)
    local pad, rowH = UI.Theme.metrics.padding, UI.Theme.px(ROW_H)
    local w, h = self:size()
    self.panel = { x = x, y = y, w = w, h = h }
    for i, row in ipairs(self.rows) do
        row.x, row.y, row.w, row.h = x + pad, y + pad + (i - 1) * rowH, w - pad * 2, rowH
    end
end

--- the rainbow value scrolls through the chroma shader
---@param row table
---@return table # a UI.TextFactory
function Readout:chromaFor(row)
    local font, text = UI.Theme.font("body"), valueText(row.spec.get())
    local chroma = self.chroma
    if not chroma or chroma.font ~= font then
        chroma = UI.TextFactory.new{ text = text, font = font, limit = row.w, align = "right" }
        self.chroma = chroma
    end
    chroma.limit, chroma.scale = row.w, UI.Theme.px(CHROMA_SPAN)
    chroma.speed = UI.Motion.reduced and 0 or CHROMA_SPEED
    chroma:setText(text)
    return chroma
end

---@param dt number
function Readout:update(dt)
    for _, row in ipairs(self.rows) do
        if row.spec.tone == "rainbow" then self:chromaFor(row):update(dt) end
    end
end

--- the bar at a row's left saying what it counts
---@param row table
---@param alpha number
function Readout:drawStripe(row, alpha)
    local Theme = UI.Theme
    local inset, w = Theme.px(STRIPE_INSET), math.max(2, Theme.px(STRIPE_W))
    local y, h = row.y + inset, row.h - inset * 2
    local tone = row.spec.tone
    if tone == "rainbow" then return self:chromaFor(row):drawChromaRect(row.x, y, w, h) end
    Theme.setColor(tone == "gold" and Theme.fixedColors.gold or Theme.colors[tone], alpha)
    love.graphics.rectangle("fill", row.x, y, w, h)
end

---@param row table
---@param y number
function Readout:drawChroma(row, y)
    local chroma = self:chromaFor(row)
    local offset = UI.Label.shadowOffset()
    chroma:setPosition(row.x, y)
    UI.Theme.setColor(UI.Theme.colors.shadow)
    love.graphics.draw(chroma.textObject, row.x + offset, y + offset)
    chroma:drawChroma()
end

---@param i integer
---@param row table
function Readout:drawRow(i, row)
    local c, alpha, tone = UI.Theme.colors, row.introAlpha, row.spec.tone
    local labelFont, valueFont = UI.Theme.font("help"), UI.Theme.font("body")

    if i > 1 then
        UI.Theme.setColor(c.panelBorder, 0.5 * alpha)
        love.graphics.rectangle("fill", row.x, row.y, row.w, math.max(1, UI.Theme.px(1)))
    end
    self:drawStripe(row, alpha)

    local labelX = row.x + UI.Theme.px(STRIPE_W + LABEL_GAP)
    UI.Label.draw{ text = I18n.t(row.spec.key), x = labelX, y = UI.Theme.centerY(row.y, row.h, labelFont),
        width = row.x + row.w - labelX, align = "left", font = labelFont, color = c.textMuted,
        alpha = alpha, shadow = true }

    local value = row.spec.get()
    local valueY = UI.Theme.centerY(row.y, row.h, valueFont)
    if tone == "rainbow" and value then return self:drawChroma(row, valueY) end
    UI.Label.draw{ text = valueText(value), x = row.x, y = valueY, width = row.w, align = "right",
        font = valueFont, alpha = alpha, shadow = true,
        color = not value and c.textDim or tone == "gold" and UI.Theme.fixedColors.gold or c.accent }
end

function Readout:draw()
    local p = self.panel
    UI.Theme.panel(p.x, p.y, p.w, p.h)
    for i, row in ipairs(self.rows) do self:drawRow(i, row) end
end

---@return boolean # any value has arrived
function Readout:hasValues()
    for _, spec in ipairs(ROWS) do
        if spec.get() ~= nil then return true end
    end
    return false
end

return Readout
