-- lib/ui/progressBar.lua
-- The glowing progress bar (extracted from the loading state): eased fill,
-- pulsing additive halo, optional percentage readout.
--
--   local bar = ProgressBar.new{}
--   bar:setProgress(0.4)   -- target; the shown fill eases toward it
--   bar:update(dt)
--   bar:draw(x, y, w, h)   -- geometry can also be set once via fields

local Theme = require "lib.ui.theme"

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
        time = 0,
    }, ProgressBar)
end

function ProgressBar:setProgress(t)
    self.target = math.max(0, math.min(1, t))
end

-- True once the bar has visually reached a full target.
function ProgressBar:isComplete()
    return self.target >= 1 and self.shown >= 0.999
end

function ProgressBar:update(dt)
    self.time = self.time + dt
    self.shown = self.shown + (self.target - self.shown) * math.min(dt * self.fillSpeed, 1)
end

function ProgressBar:draw(x, y, w, h)
    self.x, self.y = x or self.x, y or self.y
    self.w, self.h = w or self.w, h or self.h

    local c, m = Theme.colors, Theme.metrics
    local radius = m.radius

    -- Track.
    love.graphics.setColor(c.track)
    love.graphics.rectangle("fill", self.x, self.y, self.w, self.h, radius, radius)

    -- Filled portion with a pulsing glow.
    local fillW = self.w * self.shown
    if fillW > 0 then
        local pulse = 0.6 + 0.4 * math.sin(self.time * self.pulseSpeed)
        Theme.glowRect(self.x, self.y, fillW, self.h, radius, pulse)
        love.graphics.setColor(c.accent)
        love.graphics.rectangle("fill", self.x, self.y, fillW, self.h, radius, radius)
    end

    -- Outline.
    love.graphics.setColor(c.panelBorder)
    love.graphics.rectangle("line", self.x, self.y, self.w, self.h, radius, radius)

    if self.showPercent then
        local previousFont = love.graphics.getFont()
        local font = Theme.font("small")
        love.graphics.setFont(font)
        love.graphics.setColor(c.text)
        local percent = math.floor(self.shown * 100 + 0.5) .. "%"
        love.graphics.printf(percent, self.x, self.y + (self.h - font:getHeight()) / 2, self.w, "center")
        love.graphics.setFont(previousFont)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return ProgressBar
