--- A row of colour swatches from the live theme, so a player can compare
-- palettes without leaving the screen. Reads Theme.colors at draw time, so a
-- theme switch just shows up next frame.
--
--   local swatches = Swatches.new()

local PreviewRow = require("ui.widgets.preview.previewRow")
local Theme = require("ui.core.theme")
local Widget = require("ui.widgets.widget")

local Swatches = Widget.extend({}, PreviewRow)

local SIZE = 22 -- design px
local GAP = 8
local ROLES = { "accent", "accentBright", "panel", "text", "danger" }

---@param config? table # Widget.new's fields
---@return table
function Swatches.new(config)
    return PreviewRow.new(Swatches, config)
end

function Swatches:contentHeight()
    return Theme.px(SIZE)
end

---@param alpha number
function Swatches:drawContent(alpha)
    local c = Theme.colors
    local size, gap = Theme.px(SIZE), Theme.px(GAP)
    local x, y = self.x + Theme.metrics.padding, self.y + (self.h - size) / 2
    for _, role in ipairs(ROLES) do
        Theme.setColor(c[role], alpha)
        love.graphics.rectangle("fill", x, y, size, size)
        Theme.setColor(c.panelBorder, alpha)
        love.graphics.rectangle("line", x, y, size, size)
        x = x + size + gap
    end
end

return Swatches
