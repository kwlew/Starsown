-- lib/ui/selector.lua
-- Labeled discrete-option cycler: label on the left, "< value >" on the right.
-- Left/right arrows (keyboard or clicking the arrow chevrons) step through the
-- options list; clicking the value advances forward; Enter advances forward.
-- Generic — use it for resolution, quality presets, difficulty, etc.
--
--   local s = Selector.new{
--       label = "Resolution",
--       options = { {1280,720}, {1600,900}, {1920,1080} },
--       index = 1,                                    -- which option starts selected
--       format = function(o) return o[1].."x"..o[2] end,
--       onChange = function(option, index) ... end,   -- fired on every change
--   }
--
-- Sync its display without firing onChange by setting `s.index` directly.

local Theme = require "lib.ui.theme"
local Widget = require "lib.ui.widget"
local Math = require "lib.utils.math"

local Selector = {}
Widget.extend(Selector)

-- Design-space px, scaled through Theme.px at use.
local ARROW_W = 28    -- hit/draw width of each chevron
local ARROW_H = 8     -- half-height of the chevron triangle
local ARROW_BACK = 5  -- chevron's flat edge, from its center
local ARROW_TIP = 6   -- chevron's point, from its center
local VALUE_PAD = 16  -- breathing room either side of the widest value
local LABEL_MIN_W = 120 -- label space the value column may never eat into

function Selector.new(config)
    local self = Widget.new(Selector, config)
    self.options = config.options or {}
    self.index = config.index or 1
    self.format = config.format or tostring -- option -> display string
    self.onChange = config.onChange
    self.wrap = config.wrap ~= false        -- cycle past the ends (default true)
    self.valueWidth = config.valueWidth or 190 -- fits "1920x1080" at the body font
    self.hoverLeft = false
    self.hoverRight = false
    return self
end

function Selector:selected()
    return self.options[self.index]
end

function Selector:displayText()
    local option = self.options[self.index]
    if option == nil then return "--" end
    return self.format(option)
end

-- Width of the value column: `valueWidth` as a floor, grown to fit the widest
-- option once formatted, and capped so the label always keeps LABEL_MIN_W.
--
-- Sizing to the content is what keeps a long translation ("Pantalla Completa")
-- at the same size as a short one. Falling back to a fixed column and scaling
-- the text down to fit meant neighbouring rows rendered their values at visibly
-- different sizes; the down-scale in draw is now only a last resort for a row
-- too narrow to satisfy even this.
function Selector:valueColumnWidth(font)
    local m = Theme.metrics
    local width = Theme.px(self.valueWidth)
    for _, option in ipairs(self.options) do
        width = math.max(width, font:getWidth(self.format(option)) + Theme.px(VALUE_PAD))
    end
    local available = self.w - m.padding * 2 - Theme.px(ARROW_W) * 2 - Theme.px(LABEL_MIN_W)
    return Math.clamp(width, 0, available)
end

-- Left chevron, value area, and right chevron rects (right-aligned in the row).
function Selector:controlRects()
    local m = Theme.metrics
    local arrowW = Theme.px(ARROW_W)
    local valueW = self:valueColumnWidth(self:getFont())
    local rightArrowX = self.x + self.w - m.padding - arrowW
    local valueX = rightArrowX - valueW
    local leftArrowX = valueX - arrowW
    return
        { x = leftArrowX,  y = self.y, w = arrowW, h = self.h },
        { x = valueX,      y = self.y, w = valueW, h = self.h },
        { x = rightArrowX, y = self.y, w = arrowW, h = self.h }
end

function Selector:setIndex(index)
    if not self:isInteractive() then return end
    local count = #self.options
    if count == 0 then return end
    index = self.wrap and Math.wrapIndex(index, count) or Math.clamp(index, 1, count)
    if index == self.index then return end
    self.index = index
    if self.onChange then
        self.onChange(self.options[index], index)
    end
end

-- Keyboard left/right (direction is -1 or 1).
function Selector:adjust(direction)
    self:setIndex(self.index + direction)
end

-- Enter/click on the value: advance forward.
function Selector:activate()
    self:adjust(1)
end

-- Returns false: a selector has no drag, so it never captures the mouse.
function Selector:mousepressed(px, py, mouseButton)
    if mouseButton ~= 1 then return false end
    local left, value, right = self:controlRects()
    if Theme.pointIn(px, py, left.x, left.y, left.w, left.h) then
        self:adjust(-1)
    elseif Theme.pointIn(px, py, right.x, right.y, right.w, right.h) then
        self:adjust(1)
    elseif Theme.pointIn(px, py, value.x, value.y, value.w, value.h) then
        self:adjust(1)
    end
    return false
end

function Selector:mousemoved(px, py)
    if not self:isInteractive() then
        self.hoverLeft, self.hoverRight = false, false
        return
    end
    local left, _, right = self:controlRects()
    self.hoverLeft = Theme.pointIn(px, py, left.x, left.y, left.w, left.h)
    self.hoverRight = Theme.pointIn(px, py, right.x, right.y, right.w, right.h)
end

-- Draws a chevron centered in `rect`, pointing left (dir -1) or right (dir 1).
local function drawChevron(rect, dir, active, alpha)
    local cx = rect.x + rect.w / 2
    local cy = rect.y + rect.h / 2
    local half = Theme.px(ARROW_H)
    local back, tip = Theme.px(ARROW_BACK), Theme.px(ARROW_TIP)
    Theme.setColor(active and Theme.colors.accent or Theme.colors.textDim, alpha)
    if dir < 0 then
        love.graphics.polygon("fill", cx + back, cy - half, cx + back, cy + half, cx - tip, cy)
    else
        love.graphics.polygon("fill", cx - back, cy - half, cx - back, cy + half, cx + tip, cy)
    end
end

function Selector:draw()
    local alpha, font = self:alpha(), self:getFont()
    self:drawRow(alpha)

    Theme.pushFont(font)
    self:drawLabel(font, alpha)

    -- Right-side control: chevron, value, chevron.
    local left, value, right = self:controlRects()
    local live = self:isInteractive()
    drawChevron(left, -1, live and (self.hoverLeft or self.focused), alpha)
    drawChevron(right, 1, live and (self.hoverRight or self.focused), alpha)
    Theme.setColor(Theme.colors.text, alpha)
    -- Draw the value on a single line, scaled down to fit the fixed value
    -- column when a translated string is wider than it (e.g. Spanish
    -- "Pantalla Completa") — printf would wrap it onto two lines instead.
    local vtext = self:displayText()
    local vw = font:getWidth(vtext)
    local scale = vw > 0 and math.min(1, value.w / vw) or 1
    local vx = value.x + (value.w - vw * scale) / 2
    local vy = self.y + (self.h - font:getHeight() * scale) / 2
    love.graphics.print(vtext, vx, vy, 0, scale, scale)

    Theme.popFont()
    love.graphics.setColor(1, 1, 1, 1)
end

return Selector
