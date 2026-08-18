-- src/ui/progressBar.lua
-- The glowing progress bar (extracted from the loading state): eased fill,
-- pulsing additive halo, optional percentage readout.
--
--   local bar = ProgressBar.new{}
--   bar:setProgress(0.4)   -- target; the shown fill eases toward it
--   bar:update(dt)
--   bar:draw(x, y, w, h)   -- geometry can also be set once via fields

local Theme = require "ui.core.theme"
local Math = require "utils.math"

local ProgressBar = {}
ProgressBar.__index = ProgressBar

function ProgressBar.new(config)
    config = config or {}
    return setmetatable({
        x = config.x or 0,
        y = config.y or 0,
        w = config.w or 300,
        h = config.h or 26,
        target = 0,
        shown = 0, -- eased toward target for a smooth fill
        fillSpeed = config.fillSpeed or 6,
        pulseSpeed = config.pulseSpeed or 4,
        showPercent = config.showPercent ~= false,
        -- Global opacity, so an owning screen can fade the bar out as part of
        -- a transition. Set the field directly before drawing.
        alpha = config.alpha or 1,
        -- Fill colour, for a bar that means something other than "progress".
        -- nil takes the accent, which is what every bar in the UI wants; the
        -- wave timer switches to `warning` on a boss wave. Set the field
        -- directly to change it between frames.
        color = config.color,
        time = 0,
    }, ProgressBar)
end

function ProgressBar:setProgress(t)
    self.target = Math.clamp01(t)
end

function ProgressBar:isComplete()
    return self.target >= 1 and self.shown >= 0.995
end

function ProgressBar:update(dt)
    self.time = self.time + dt
    self.shown = Theme.approach(self.shown, self.target, dt, self.fillSpeed)
end

function ProgressBar:draw(x, y, w, h)
    self.x, self.y = x or self.x, y or self.y
    self.w, self.h = w or self.w, h or self.h

    local c, m = Theme.colors, Theme.metrics
    local radius = m.radius
    local alpha = self.alpha
    if alpha <= 0 then return end

    -- Track.
    Theme.setColor(c.track, alpha)
    love.graphics.rectangle("fill", self.x, self.y, self.w, self.h, radius, radius)

    -- Filled portion with a pulsing glow.
    local fill = self.color or c.accent
    local fillW = self.w * self.shown
    if fillW > 0 then
        local pulse = 0.4 + 0.4 * math.sin(self.time * self.pulseSpeed)
        Theme.glowRect(self.x, self.y, fillW, self.h, radius, pulse * alpha, fill)
        Theme.setColor(fill, alpha)
        love.graphics.rectangle("fill", self.x, self.y, fillW, self.h, radius, radius)
    end

    -- Outline.
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
