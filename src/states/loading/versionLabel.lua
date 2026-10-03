--- The version label, eased from big-and-centred to the menu corner.

local App = require("core.app")
local UI = require("ui")

local VersionLabel = {}
VersionLabel.__index = VersionLabel

local BIG_SIZE = 64      -- design pt, rasterized natively for crispness
local BIG_Y_RATIO = 0.85
VersionLabel.CORNER_PAD = 12

---@return table
function VersionLabel.new()
    local self = setmetatable({}, VersionLabel)
    self:rebuild()
    return self
end

--- re-rasterizes at the current UI scale
function VersionLabel:rebuild()
    self.small = UI.Theme.font("small")
    self.big = love.graphics.newText(UI.Theme.fontSized("small", BIG_SIZE), App.VERSION)
    self:layout()
end

--- both poses: the menu pose matches the main menu exactly
function VersionLabel:layout()
    local w, h = love.graphics.getDimensions()
    local pad = UI.Theme.px(VersionLabel.CORNER_PAD)
    local smallW, smallH = self.small:getWidth(App.VERSION), self.small:getHeight()

    self.endScale = smallH / self.big:getHeight()
    self.bigX, self.bigY = (w - self.big:getWidth()) / 2, h * BIG_Y_RATIO
    self.menuX, self.menuY = w - smallW - pad, h - pad - smallH
end

---@param ease number # 0 big .. 1 menu corner
function VersionLabel:draw(ease)
    local c = UI.Theme.colors
    local scale = 1 + (self.endScale - 1) * ease
    love.graphics.push()
    love.graphics.translate(self.bigX + (self.menuX - self.bigX) * ease, self.bigY + (self.menuY - self.bigY) * ease)
    love.graphics.scale(scale)
    love.graphics.setColor(UI.Theme.lerp(c.text, c.textDim, ease))
    love.graphics.draw(self.big, 0, 0)
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)
end

return VersionLabel
