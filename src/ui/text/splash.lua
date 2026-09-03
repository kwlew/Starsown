--- One line of flavor text under the title, picked once per session from
-- menu.splashes.1, .2, ... in assets/lang/* (see I18n.list).

local Theme = require "ui.core.theme"
local I18n = require "core.i18n"
local Math = require "utils.math"
local Motion = require "ui.core.motion"

local Splash = {}
Splash.__index = Splash

local FONT_ROLE = "small"
local GAP = 14
local SHADOW_OFFSET = 2
local BOB_SPEED = 1
local BOB_AMOUNT = 2
local FADE_IN_TIME = 1.4 -- seconds

--- "" when the active locale has no splashes; draws as nothing
---@return table splash
function Splash.pick()
    local lines = I18n.list("menu.splashes")
    return setmetatable({
        text = #lines > 0 and lines[Math.randInt(1, #lines)] or "",
        textObject = nil,
        textValue = nil,
        textFont = nil,
        textWidth = 0,
        time = Math.randRange(0, 10),
        age = 0, -- separate from `time`, whose random phase would skip the fade-in
    }, Splash)
end

---@param dt number
function Splash:update(dt)
    self.time = self.time + dt
    self.age = self.age + dt
end

--- centred beneath a title, fading in once and then drifting faintly
---@param title table # the TextFactory it sits under; read for its y and height
---@param windowW number
function Splash:draw(title, windowW)
    if self.text == "" then return end

    local font = Theme.font(FONT_ROLE)
    if self.textValue ~= self.text or self.textFont ~= font then
        self.textObject = love.graphics.newText(font, self.text)
        self.textValue = self.text
        self.textFont = font
        self.textWidth = self.textObject:getWidth()
    end

    local bob = Motion.reduced and 0 or math.sin(self.time * BOB_SPEED) * Theme.px(BOB_AMOUNT)
    local x = windowW / 2 - self.textWidth / 2
    local y = title.y + title.textObject:getHeight() + Theme.px(GAP) + bob

    local alpha = Motion.reduced and 1 or Math.clamp01(self.age / FADE_IN_TIME)

    local offset = Theme.px(SHADOW_OFFSET)
    local shadow = Theme.colors.shadow
    Theme.setColor(shadow, alpha * (shadow[4] or 1))
    love.graphics.draw(self.textObject, x + offset, y + offset)
    Theme.setColor(Theme.colors.accent, alpha)
    love.graphics.draw(self.textObject, x, y)

    love.graphics.setColor(1, 1, 1, 1)
end

return Splash
