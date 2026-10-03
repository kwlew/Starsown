--- Places the Options screen: heading, tabs, rows panel, footer, notes.
-- Fixed parts first; the scrolling rows get what's left.

local I18n = require("core.i18n")
local UI = require("ui")

local Layout = {}

local MARGIN = 24
local GAP = 10
local PANEL_PAD = 10
local PANEL_MAX_W = 720
local SEGMENT_GAP = 6
local TEXT_PAD = 12
local HINT_BOTTOM = 16

---@param font any
---@param text string
---@param width number
---@return number
local function textHeight(font, text, width)
    local _, lines = font:getWrap(text, width)
    return math.max(1, #lines) * font:getHeight()
end

---@param labels string[]
---@param font any
---@param width number
---@return number
local function rowHeightFor(labels, font, width)
    local height = UI.Theme.metrics.rowHeight
    for _, text in ipairs(labels) do
        height = math.max(height, textHeight(font, text, width) + UI.Theme.px(TEXT_PAD))
    end
    return height
end

---@param screen table # the Options state
---@param scrollY? number
function Layout.apply(screen, scrollY)
    local px, m = UI.Theme.px, UI.Theme.metrics
    local w, h = love.graphics.getDimensions()
    local margin, gap, pad = px(MARGIN), px(GAP), px(PANEL_PAD)
    local panelW = math.min(px(PANEL_MAX_W), w - margin * 2)
    local panelX = (w - panelW) / 2
    local small, buttonFont = UI.Theme.font("small"), UI.Theme.font("button")

    screen.headingY = margin

    local tabLabels = {}
    for i, name in ipairs(screen.tabBar.tabs) do tabLabels[i] = UI.Theme.resolveLabel(name, screen.tabBar) end
    local tabH = rowHeightFor(tabLabels, buttonFont, (panelW - px(SEGMENT_GAP) * 2) / #screen.tabs)
    local tabY = screen.headingY + UI.Theme.font("heading"):getHeight() + gap
    screen.tabBar:setBounds(panelX, tabY, panelW, tabH)

    local hintH = textHeight(small, I18n.t("options.hint.navigation"), panelW)
    screen.hintRect = { x = panelX, y = h - px(HINT_BOTTOM) - hintH, w = panelW, h = hintH }

    local footer = screen:footerButtons()
    local buttonW = (panelW - m.rowGap) / #footer
    local footerLabels = {}
    for i, button in ipairs(footer) do footerLabels[i] = button:labelText() end
    local footerH = rowHeightFor(footerLabels, buttonFont, buttonW)
    local footerY = screen.hintRect.y - gap - footerH
    for i, button in ipairs(footer) do
        button:setBounds(panelX + (i - 1) * (buttonW + m.rowGap), footerY, buttonW, footerH)
    end

    local statusH = textHeight(small, I18n.t("options.pendingGraphics"), panelW)
    screen.statusRect = { x = panelX, y = footerY - gap - statusH, w = panelW, h = statusH }

    local panelY = tabY + tabH + gap
    local panelH = math.max(1, screen.statusRect.y - gap - panelY)
    screen.panel = { x = panelX, y = panelY, w = panelW, h = panelH }
    screen.scroll:layout(screen.tabs[screen.activeTab].widgets, panelX + pad, panelY + pad,
        panelW - pad * 2, math.max(1, panelH - pad * 2), scrollY)

    for _, dialog in ipairs(screen:dialogs()) do dialog:layout() end
end

return Layout
