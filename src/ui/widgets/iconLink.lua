--- A small hover/press/open-URL icon button for external links (GitHub,
-- Discord, ...) -- the main menu's corner marks. Built on Widget so it can
-- join the same FocusGroup as the menu buttons: Tab reaches it and Enter
-- opens the link, instead of it being mouse-only chrome.
--
--   local link = IconLink.new{ mark = "github", url = "https://...", label = "GitHub" }
--   link:setBounds(x, y, size, size)   -- from the owning screen's layout()

local Theme = require "ui.core.theme"
local Widget = require "ui.widgets.widget"
local Marks = require "ui.icons.marks"
local Sfx = require "ui.core.sfx"

local IconLink = {}
Widget.extend(IconLink)

local HOVER_COLOR = { 0.80, 0.80, 0.80 }
local HOVER_GLOW, IDLE_GLOW = 1, 0.45

---@param config table # Widget.new's fields, plus mark: string, url: string
---@return table
function IconLink.new(config)
    local self = Widget.new(IconLink, config)
    self.mark = config.mark -- name in ui.icons.marks
    self.url = config.url
    self.hover = false
    self.pressed = false
    return self
end

---@param px number
---@param py number
function IconLink:mousemoved(px, py)
    self.hover = self:contains(px, py)
end

--- returns true if it captured the click, so a caller can stop routing it
-- further down (to another link, or the starfield behind everything)
---@param px number
---@param py number
---@param button integer
---@return boolean captured
function IconLink:mousepressed(px, py, button)
    if button ~= 1 or not self:contains(px, py) then return false end
    self.pressed = true
    Sfx.press()
    return true
end

--- opens the URL in the player's browser, but only on a full press+release on
-- the mark -- not a click that drags off
---@param px number
---@param py number
---@param button integer
function IconLink:mousereleased(px, py, button)
    if button ~= 1 or not self.pressed then return end
    self.pressed = false
    if self:contains(px, py) then
        love.system.openURL(self.url)
    end
end

--- Enter, for a keyboard-focused link -- the same action a full click performs
function IconLink:activate()
    Sfx.press()
    love.system.openURL(self.url)
end

--- brighter, with a stronger bloom, while hovered or keyboard-focused
function IconLink:draw()
    local lit = self.hover or self.focused
    Marks.draw(self.mark, self.x, self.y, self.w,
        lit and HOVER_COLOR or Theme.colors.textDim,
        lit and HOVER_GLOW or IDLE_GLOW)
end

return IconLink
