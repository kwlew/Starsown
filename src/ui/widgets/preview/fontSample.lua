--- A line of sample text in a font role, so a player can compare typefaces
-- without leaving the screen. The role may be a function, read every draw,
-- so a font switch just shows up next frame.
--
--   local titleSample = FontSample.new{ text = GameTitle.TEXT, role = GameTitle.currentRole }
--   local uiSample = FontSample.new{ text = "AaBbCc 0123", role = "button" }

local PreviewRow = require("ui.widgets.preview.previewRow")
local Theme = require("ui.core.theme")
local Widget = require("ui.widgets.widget")

local FontSample = Widget.extend({}, PreviewRow)

local SAMPLE_SIZE = 30 -- design-space point size for the inline sample

---@param config table # Widget.new's fields, plus text: string, role: string|fun(): string
---@return table
function FontSample.new(config)
    local self = PreviewRow.new(FontSample, config)
    self.text = config.text or ""
    self.role = config.role
    self.font, self.fontKey = nil, nil
    return self
end

--- Theme.fontSized rasterizes a new Font every call, so it's rebuilt only
-- when the role, the interface family or the UI scale actually changed
---@return any # a love.Font
function FontSample:sampleFont()
    local role = type(self.role) == "function" and self.role() or self.role
    local key = table.concat({ role, Theme.currentUiFontFamily(), Theme.scale }, "|")
    if key ~= self.fontKey then
        self.font, self.fontKey = Theme.fontSized(role, SAMPLE_SIZE), key
    end
    return self.font
end

function FontSample:contentHeight()
    return self:sampleFont():getHeight()
end

---@param alpha number
function FontSample:drawContent(alpha)
    local font = self:sampleFont()
    Theme.pushFont(font)
    Theme.setColor(Theme.colors.accentBright, alpha)
    love.graphics.print(self.text, self.x + Theme.metrics.padding, self.y + (self.h - font:getHeight()) / 2)
    Theme.popFont()
end

return FontSample
