-- One line of flavor text under the title, picked once per session from
-- menu.splashes.1, .2, ... in assets/lang/* (see I18n.list).

local Theme = require "ui.core.theme"
local I18n = require "core.i18n"
local Math = require "utils.math"
local Motion = require "ui.core.motion"

local Splash = {}
Splash.__index = Splash

-- design-space px except where noted; scaled through Theme.px at use
local FONT_ROLE = "small"
local GAP = 14
local SHADOW_OFFSET = 2
local BOB_SPEED = 1
local BOB_AMOUNT = 2
local FADE_IN_TIME = 1.4 -- seconds

-- "" when the active locale has no splashes; draws as nothing
function Splash.pick()
    local lines = I18n.list("menu.splashes")
    return setmetatable({
        text = #lines > 0 and lines[Math.randInt(1, #lines)] or "",
        time = Math.randRange(0, 10),
        age = 0, -- separate from `time`, whose random phase would skip the fade-in
    }, Splash)
end

function Splash:update(dt)
    self.time = self.time + dt
    self.age = self.age + dt
end

-- centered under `title` (a TextFactory instance, e.g. GameTitle's)
function Splash:draw(title, windowW)
    if self.text == "" then return end

    local font = Theme.font(FONT_ROLE)
    local textW = font:getWidth(self.text)

    local bob = Motion.reduced and 0 or math.sin(self.time * BOB_SPEED) * Theme.px(BOB_AMOUNT)
    local x = windowW / 2 - textW / 2
    local y = title.y + title.textObject:getHeight() + Theme.px(GAP) + bob

    local alpha = Motion.reduced and 1 or Math.clamp01(self.age / FADE_IN_TIME)

    Theme.pushFont(font)
    local offset = Theme.px(SHADOW_OFFSET)
    local shadow = Theme.colors.shadow
    Theme.setColor(shadow, alpha * (shadow[4] or 1))
    love.graphics.print(self.text, x + offset, y + offset)
    Theme.setColor(Theme.colors.accent, alpha)
    love.graphics.print(self.text, x, y)
    Theme.popFont()

    love.graphics.setColor(1, 1, 1, 1)
end

return Splash
