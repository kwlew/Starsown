--- The base of the decorative settings rows that preview a choice (a theme's
-- colours, a font's letterforms). Never focused or clicked, and not dimmed
-- like a disabled row -- dimming would read as broken, not decorative.
--
-- A subclass answers contentHeight() and drawContent().

local Theme = require("ui.core.theme")
local Widget = require("ui.widgets.widget")

local PreviewRow = Widget.extend({})

local V_PAD = 16 -- design px, total above and below the content

---@param class table
---@param config? table # Widget.new's fields
---@return table
function PreviewRow.new(class, config)
    local self = Widget.new(class, config or {})
    self.enabled = false -- never takes focus or clicks
    return self
end

--- the same rowLayout shape every other row leaves, since shared code reads it
---@param width number
---@return number height
function PreviewRow:measureRow(width)
    local height = math.max(Theme.metrics.rowHeight, self:contentHeight() + Theme.px(V_PAD))
    self.rowLayout = { stacked = true, x = 0, y = 0, w = width, h = height }
    return height
end

function PreviewRow:draw()
    self:drawRow(self.introAlpha)
    self:drawContent(self.introAlpha)
    love.graphics.setColor(1, 1, 1, 1)
end

return PreviewRow
