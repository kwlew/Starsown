--- Decorative, unfocusable row: a small preview of the currently selected
-- theme or title font, so a player can compare options without leaving the
-- screen. Reads live theme/font state at draw time, so it needs no wiring
-- from the selector rows above it -- changing either just shows up next frame.
--
--   local swatches = Preview.newTheme{}
--   local sample = Preview.newTitleFont{}

local Theme = require "ui.core.theme"
local Widget = require "ui.widgets.widget"
local GameTitle = require "ui.text.gameTitle"

local Preview = {}
Widget.extend(Preview)

local SWATCH = 22 -- design-space px, scaled through Theme.px
local SWATCH_GAP = 8
local SAMPLE_SIZE = 30 -- design-space title-font point size for the inline sample
local SWATCH_ROLES = { "accent", "accentBright", "panel", "text", "danger" }

---@param config table # Widget.new's fields
---@param kind "theme"|"title"
---@return table
local function new(config, kind)
    local self = Widget.new(Preview, config)
    self.enabled = false -- decorative: never takes focus, click, or the disabled-dim look
    self.kind = kind
    return self
end

---@return table
function Preview.newTheme(config)
    return new(config or {}, "theme")
end

---@return table
function Preview.newTitleFont(config)
    return new(config or {}, "title")
end

--- Rebuilt only when the selected face actually changes -- Theme.fontSized
-- rasterizes a new Font each call, so caching this is what keeps a draw call
-- cheap. `Theme.rescale` also changes the design-to-screen scale, so a
-- resize needs to invalidate this the same as a font switch does.
---@return any # a love.Font, sized for an inline sample rather than the full title
function Preview:sampleFont()
    if self.fontId ~= GameTitle.current or self.fontScale ~= Theme.scale then
        self.fontId, self.fontScale = GameTitle.current, Theme.scale
        self.font = Theme.fontSized(GameTitle.currentRole(), SAMPLE_SIZE)
    end
    return self.font
end

function Preview:measureRow(width)
    local contentH = self.kind == "theme" and Theme.px(SWATCH) or self:sampleFont():getHeight()
    local height = math.max(Theme.metrics.rowHeight, contentH + Theme.px(16))
    -- Satisfies the same rowLayout shape every other row's measureRow leaves,
    -- since shared code (ScrollArea, the row-chrome background) reads it.
    self.rowLayout = { stacked = true, x = 0, y = 0, w = width, h = height }
    return height
end

--- alpha bypasses Widget:alpha()'s disabled-dim -- this isn't disabled, it's
-- decorative, and dimming it would read as broken rather than intentional.
function Preview:draw()
    self:drawRow(self.introAlpha)
    if self.kind == "theme" then self:drawSwatches() else self:drawSample() end
end

function Preview:drawSwatches()
    local c, m = Theme.colors, Theme.metrics
    local swatch, gap = Theme.px(SWATCH), Theme.px(SWATCH_GAP)
    local x, y = self.x + m.padding, self.y + (self.h - swatch) / 2
    for _, role in ipairs(SWATCH_ROLES) do
        Theme.setColor(c[role], self.introAlpha)
        love.graphics.rectangle("fill", x, y, swatch, swatch, Theme.px(4), Theme.px(4))
        Theme.setColor(c.panelBorder, self.introAlpha)
        love.graphics.rectangle("line", x, y, swatch, swatch, Theme.px(4), Theme.px(4))
        x = x + swatch + gap
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function Preview:drawSample()
    local font = self:sampleFont()
    Theme.pushFont(font)
    Theme.setColor(Theme.colors.accentBright, self.introAlpha)
    love.graphics.print(GameTitle.TEXT, self.x + Theme.metrics.padding, self.y + (self.h - font:getHeight()) / 2)
    Theme.popFont()
    love.graphics.setColor(1, 1, 1, 1)
end

return Preview
