--- Measured label/control layout for a settings row: the label on the left,
-- the widget's control on the right, or stacked label-over-control when
-- both won't fit side by side. Positions are relative to the row, so they
-- survive scrolling without another measure pass.
--
-- A widget opts in by answering preferredControlSize(available) -> w, h.

local Theme = require("ui.core.theme")

local RowLayout = {}

local V_PAD = 8 -- design px above and below the content
local GAP = 6   -- design px between a stacked label and its control

---@param widget table # must answer getFont, labelText, preferredControlSize
---@param width number # the row's width
---@return table layout # { labelX, labelY, labelW, labelH, x, y, w, h, stacked }; the control rect is x/y/w/h
---@return number height # the row's height
function RowLayout.measure(widget, width)
    local m, font = Theme.metrics, widget:getFont()
    local label = widget:labelText()
    local inner = math.max(1, width - m.padding * 2)

    local controlW, controlH = widget:preferredControlSize(inner)
    controlW = math.min(inner, controlW)

    local stacked = font:getWidth(label) + m.padding + controlW > inner
    local labelW = stacked and inner or math.max(1, inner - controlW - m.padding)
    local _, lines = font:getWrap(label, labelW)
    local labelH = math.max(1, #lines) * font:getHeight()

    local vpad, gap = Theme.px(V_PAD), Theme.px(GAP)
    local contentH = stacked and labelH + gap + controlH or math.max(labelH, controlH)
    local height = math.max(m.rowHeight, contentH + vpad * 2)

    return {
        labelX = m.padding, labelY = stacked and vpad or (height - labelH) / 2,
        labelW = labelW, labelH = labelH,
        x = width - m.padding - controlW,
        y = stacked and vpad + labelH + gap or (height - controlH) / 2,
        w = controlW, h = controlH, stacked = stacked,
    }, height
end

return RowLayout
