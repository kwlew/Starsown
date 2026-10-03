--- A staggered entrance: fades a list of widgets in top to bottom by easing
-- each one's introAlpha. Does nothing under reduced motion.
--
--   self.intro = Intro.new()
--   self.intro:play(menu:buttons())
--   self.intro:update(dt)

local Ease = require("utils.ease")
local Math = require("utils.math")
local Motion = require("ui.core.motion")

local Intro = {}
Intro.__index = Intro

local DURATION = 1.2
local STAGGER = 0.01

---@param config? table # { duration?: number, stagger?: number }
---@return table
function Intro.new(config)
    config = config or {}
    return setmetatable({
        duration = config.duration or DURATION,
        stagger = config.stagger or STAGGER,
        widgets = nil,
        time = nil, -- nil when not playing
    }, Intro)
end

---@param widgets table[]
function Intro:play(widgets)
    if Motion.reduced then return end -- reduced motion: they're just there, no cascade
    self.widgets, self.time = widgets, 0
    for _, widget in ipairs(widgets) do widget.introAlpha = 0 end
end

---@return boolean
function Intro:isPlaying()
    return self.time ~= nil
end

---@param dt number
function Intro:update(dt)
    if not self.time then return end
    self.time = self.time + dt

    local finished = true
    for i, widget in ipairs(self.widgets) do
        local t = (self.time - (i - 1) * self.stagger) / self.duration
        if t < 1 then finished = false end
        widget.introAlpha = Ease.outCubic(Math.clamp01(t))
    end
    if finished then self.widgets, self.time = nil, nil end
end

return Intro
