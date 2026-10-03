--- One line of flavour text under the title, picked once per session. The
-- caller supplies the candidate lines (from whatever translation system is
-- current), so this only owns how it looks and moves.
--
--   local splash = Splash.pick(I18n.list("menu.splashes"))
--   splash:update(dt)
--   splash:draw(title, windowW)

local Math = require("utils.math")
local Motion = require("ui.core.motion")
local Theme = require("ui.core.theme")
local Label = require("ui.text.label")

local Splash = {}
Splash.__index = Splash

local FONT_ROLE = "help"
local GAP = 14
local BOB_SPEED = 0.1
local BOB_AMOUNT = 1
local FADE_IN_TIME = 1.4 -- seconds

---@param lines string[] # candidates; empty draws nothing
---@return table splash
function Splash.pick(lines)
    return setmetatable({
        text = #lines > 0 and lines[Math.randInt(1, #lines)] or "",
        time = Math.randRange(0, 10), -- random phase, so the bob doesn't always start mid-swing the same way
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

    local bob = Motion.reduced and 0 or math.sin(self.time * BOB_SPEED) * Theme.px(BOB_AMOUNT)
    Label.draw{
        text = self.text,
        y = title.y + title.textObject:getHeight() + Theme.px(GAP) + bob,
        width = windowW,
        font = Theme.font(FONT_ROLE),
        color = Theme.colors.accentBright,
        alpha = Motion.reduced and 1 or Math.clamp01(self.age / FADE_IN_TIME),
        shadow = true,
    }
end

return Splash
