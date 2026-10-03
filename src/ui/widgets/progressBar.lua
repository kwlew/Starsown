--- A glowing progress bar: eased fill, pulsing additive halo, optional
-- percentage readout. Not a Widget -- it's never focused or clicked.
--
--   local bar = ProgressBar.new{}
--   bar:setProgress(0.4) -- the target; the shown fill eases toward it
--   bar:update(dt)
--   bar:draw(x, y, w, h)

local Math = require("utils.math")
local Theme = require("ui.core.theme")

local ProgressBar = {}
ProgressBar.__index = ProgressBar

local PULSE_BASE, PULSE_AMOUNT = 0.4, 0.4

---@param config? table # { x?: number, y?: number, w?: number, h?: number, fillSpeed?: number, pulseSpeed?: number, showPercent?: boolean, alpha?: number, color?: number[] }
---@return table
function ProgressBar.new(config)
    config = config or {}
    return setmetatable({
        x = config.x or 0,
        y = config.y or 0,
        w = config.w or 300,
        h = config.h or 26,
        target = 0,
        shown = 0,
        fillSpeed = config.fillSpeed or 6,
        pulseSpeed = config.pulseSpeed or 4,
        showPercent = config.showPercent ~= false,
        alpha = config.alpha or 1, -- set directly to fade the bar out
        color = config.color,      -- nil takes the theme accent
        time = 0,
    }, ProgressBar)
end

---@param t number # 0..1
function ProgressBar:setProgress(t)
    self.target = Math.clamp01(t)
end

---@return boolean # true once the eased fill has caught up, not the moment the target hits 1
function ProgressBar:isComplete()
    return self.target >= 1 and self.shown >= 0.995
end

---@param dt number
function ProgressBar:update(dt)
    self.time = self.time + dt
    self.shown = Theme.approach(self.shown, self.target, dt, self.fillSpeed)
end

--- track, glowing fill, border, and the optional readout
---@param x? number # these also set the stored geometry
---@param y? number
---@param w? number
---@param h? number
function ProgressBar:draw(x, y, w, h)
    self.x, self.y = x or self.x, y or self.y
    self.w, self.h = w or self.w, h or self.h

    local alpha = self.alpha
    if alpha <= 0 then return end
    local c, radius = Theme.colors, Theme.metrics.radius

    Theme.setColor(c.track, alpha)
    love.graphics.rectangle("fill", self.x, self.y, self.w, self.h, radius, radius)

    local fill = self.color or c.accent
    local fillW = self.w * self.shown
    if fillW > 0 then
        local pulse = PULSE_BASE + PULSE_AMOUNT * math.sin(self.time * self.pulseSpeed)
        Theme.glowRect(self.x, self.y, fillW, self.h, radius, pulse * alpha, fill)
        Theme.setColor(fill, alpha)
        love.graphics.rectangle("fill", self.x, self.y, fillW, self.h, radius, radius)
    end

    Theme.setColor(c.panelBorder, alpha)
    love.graphics.rectangle("line", self.x, self.y, self.w, self.h, radius, radius)

    if self.showPercent then
        local font = Theme.font("small")
        Theme.pushFont(font)
        Theme.setColor(c.text, alpha)
        love.graphics.printf(Math.round(self.shown * 100) .. "%",
            self.x, Theme.centerY(self.y, self.h, font), self.w, "center")
        Theme.popFont()
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return ProgressBar
