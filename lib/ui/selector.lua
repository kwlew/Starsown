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

local Selector = {}
Selector.__index = Selector

local ARROW_W = 28  -- hit/draw width of each chevron
local ARROW_H = 8   -- half-height of the chevron triangle

function Selector.new(config)
    return setmetatable({
        label = config.label or "",
        options = config.options or {},
        index = config.index or 1,
        format = config.format or tostring, -- option -> display string
        onChange = config.onChange,
        wrap = config.wrap ~= false,        -- cycle past the ends (default true)
        enabled = config.enabled ~= false,  -- disabled = greyed out and inert
        valueWidth = config.valueWidth or 190, -- fits "1920x1080" at the body font
        font = config.font or Theme.font("body"),
        x = config.x or 0,
        y = config.y or 0,
        w = config.w or 260,
        h = config.h or Theme.metrics.rowHeight,
        focused = false,
        glow = 0,
        time = 0,
        hoverLeft = false,
        hoverRight = false,
    }, Selector)
end

function Selector:selected()
    return self.options[self.index]
end

function Selector:displayText()
    local option = self.options[self.index]
    if option == nil then return "--" end
    return self.format(option)
end

function Selector:contains(px, py)
    return Theme.pointIn(px, py, self.x, self.y, self.w, self.h)
end

function Selector:labelText()
    return Theme.resolveLabel(self.label, self)
end

-- Left chevron, value area, and right chevron rects (right-aligned in the row).
function Selector:controlRects()
    local m = Theme.metrics
    local rightArrowX = self.x + self.w - m.padding - ARROW_W
    local valueX = rightArrowX - self.valueWidth
    local leftArrowX = valueX - ARROW_W
    return
        { x = leftArrowX,  y = self.y, w = ARROW_W,         h = self.h },
        { x = valueX,      y = self.y, w = self.valueWidth, h = self.h },
        { x = rightArrowX, y = self.y, w = ARROW_W,         h = self.h }
end

function Selector:setIndex(index)
    if not self.enabled then return end
    local count = #self.options
    if count == 0 then return end
    if self.wrap then
        index = (index - 1) % count + 1
    else
        index = math.max(1, math.min(count, index))
    end
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

function Selector:mousepressed(px, py, mouseButton)
    if mouseButton ~= 1 then return end
    local left, value, right = self:controlRects()
    if Theme.pointIn(px, py, left.x, left.y, left.w, left.h) then
        self:adjust(-1)
    elseif Theme.pointIn(px, py, right.x, right.y, right.w, right.h) then
        self:adjust(1)
    elseif Theme.pointIn(px, py, value.x, value.y, value.w, value.h) then
        self:adjust(1)
    end
end

function Selector:mousemoved(px, py)
    if not self.enabled then
        self.hoverLeft, self.hoverRight = false, false
        return
    end
    local left, _, right = self:controlRects()
    self.hoverLeft = Theme.pointIn(px, py, left.x, left.y, left.w, left.h)
    self.hoverRight = Theme.pointIn(px, py, right.x, right.y, right.w, right.h)
end

function Selector:update(dt)
    self.time = self.time + dt
    self.glow = Theme.approach(self.glow, (self.focused and self.enabled) and 1 or 0, dt)
end

-- Draws a chevron centered in `rect`, pointing left (dir -1) or right (dir 1).
local function drawChevron(rect, dir, active, alpha)
    local cx = rect.x + rect.w / 2
    local cy = rect.y + rect.h / 2
    local c = active and Theme.colors.accent or Theme.colors.textDim
    love.graphics.setColor(c[1], c[2], c[3], alpha)
    if dir < 0 then
        love.graphics.polygon("fill", cx + 5, cy - ARROW_H, cx + 5, cy + ARROW_H, cx - 6, cy)
    else
        love.graphics.polygon("fill", cx - 5, cy - ARROW_H, cx - 5, cy + ARROW_H, cx + 6, cy)
    end
end

function Selector:draw()
    local c, m = Theme.colors, Theme.metrics
    -- Disabled rows render at reduced alpha and never glow (update forces the
    -- glow to 0 when disabled); rowChrome fades only the border by `alpha`.
    local alpha = self.enabled and 1 or 0.4

    Theme.rowChrome(self.x, self.y, self.w, self.h, self.glow, self.time, alpha)

    local previousFont = love.graphics.getFont()
    love.graphics.setFont(self.font)
    local textY = Theme.centerY(self.y, self.h, self.font)

    -- Label, left-aligned.
    love.graphics.setColor(c.text[1], c.text[2], c.text[3], alpha)
    love.graphics.print(self:labelText(), self.x + m.padding, textY)

    -- Right-side control: chevron, value, chevron.
    local left, value, right = self:controlRects()
    drawChevron(left, -1, self.enabled and (self.hoverLeft or self.focused), alpha)
    drawChevron(right, 1, self.enabled and (self.hoverRight or self.focused), alpha)
    love.graphics.setColor(c.text[1], c.text[2], c.text[3], alpha)
    -- Draw the value on a single line, scaled down to fit the fixed value
    -- column when a translated string is wider than it (e.g. Spanish
    -- "Pantalla Completa") — printf would wrap it onto two lines instead.
    local vtext = self:displayText()
    local vw = self.font:getWidth(vtext)
    local scale = vw > 0 and math.min(1, value.w / vw) or 1
    local vx = value.x + (value.w - vw * scale) / 2
    local vy = self.y + (self.h - self.font:getHeight() * scale) / 2
    love.graphics.print(vtext, vx, vy, 0, scale, scale)

    love.graphics.setFont(previousFont)
    love.graphics.setColor(1, 1, 1, 1)
end

return Selector
