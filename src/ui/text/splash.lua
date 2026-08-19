-- The rotated splash text hanging off the title, a la Minecraft: one line of
-- flavor text, picked at random once per session, that gently pulses in place.
-- Localized -- assets/lang/*.json holds menu.splashes.1, .2, .3, ... per
-- language (see I18n.list).
--
--   self.splash = self.splash or Splash.pick() -- build once, like the menu/starfield
--   function State:update(dt) self.splash:update(dt) end
--   function State:draw() self.splash:drawNear(self.title, w) end

local Theme = require "ui.core.theme"
local I18n = require "core.i18n"
local Math = require "utils.math"
local Motion = require "ui.core.motion"

local Splash = {}
Splash.__index = Splash

local FONT_ROLE = "button"
local ANGLE = -0.22       -- radians; tilts up to the right, like a stamped tag
local PULSE_SPEED = 4
local PULSE_AMOUNT = 0.08 -- +/- scale around 1, the "breathing" bounce
local Y_FACTOR = 0.78     -- how far down the title's height the splash hangs, 0 = top
local TUCK = 0.12         -- pulls it in from the title's exact corner, x fraction of title height
local SHADOW_OFFSET = 2   -- design-space px, matches Label's

-- one random line, or "" (drawn as nothing) if the active locale has none
function Splash.pick()
    local lines = I18n.list("menu.splashes")
    return setmetatable({
        text = #lines > 0 and lines[Math.randInt(1, #lines)] or "",
        time = Math.randRange(0, 10), -- phase offset, in case more than one is ever on screen
    }, Splash)
end

function Splash:update(dt)
    self.time = self.time + dt
end

-- pinned to the upper-right corner of `title` (a TextFactory instance, e.g.
-- GameTitle's), the way Minecraft hangs its splash off the logo
function Splash:drawNear(title, windowW)
    if self.text == "" then return end

    local font = Theme.font(FONT_ROLE)
    local pulse = Motion.reduced and 0 or PULSE_AMOUNT -- reduced motion: no breathing bounce
    local scale = 1 + math.sin(self.time * PULSE_SPEED) * pulse
    local ox, oy = font:getWidth(self.text) / 2, font:getHeight() / 2

    local titleW, titleH = title.textObject:getWidth(), title.textObject:getHeight()
    local x = windowW / 2 + titleW / 2 - titleH * TUCK
    local y = title.y + titleH * Y_FACTOR

    Theme.pushFont(font)
    local offset = Theme.px(SHADOW_OFFSET)
    Theme.setColor(Theme.colors.shadow)
    love.graphics.print(self.text, x + offset, y + offset, ANGLE, scale, scale, ox, oy)
    Theme.setColor(Theme.colors.warning)
    love.graphics.print(self.text, x, y, ANGLE, scale, scale, ox, oy)
    Theme.popFont()

    love.graphics.setColor(1, 1, 1, 1)
end

return Splash
