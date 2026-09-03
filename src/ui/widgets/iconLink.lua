--- A small hover/press/open-URL icon button for external links (GitHub,
-- Discord, ...) -- the main menu's corner marks. Not on the Widget base:
-- these live outside any FocusGroup (mouse-only, no keyboard focus), so
-- there's no glow/label/enabled contract to inherit.
--
--   local link = IconLink.new{ mark = "github", url = "https://..." }
--   link:setBounds(x, y, size, size)   -- from the owning screen's layout()
--   link:mousemoved(x, y) / :mousepressed(x, y, button) / :mousereleased(x, y, button)
--   link:draw()

local Theme = require "ui.core.theme"
local Marks = require "ui.icons.marks"
local Sfx = require "ui.core.sfx"

local IconLink = {}
IconLink.__index = IconLink

local HOVER_COLOR = { 0.80, 0.80, 0.80 }
local HOVER_GLOW, IDLE_GLOW = 1, 0.45

---@param config table # { mark: string, url: string }
---@return table
function IconLink.new(config)
    return setmetatable({
        mark = config.mark, -- name in ui.icons.marks
        url = config.url,
        x = 0, y = 0, w = 0, h = 0,
        hover = false,
        pressed = false,
    }, IconLink)
end

---@param x number
---@param y number
---@param w number
---@param h number
function IconLink:setBounds(x, y, w, h)
    self.x, self.y, self.w, self.h = x, y, w, h
end

---@param px number
---@param py number
---@return boolean
function IconLink:contains(px, py)
    return Theme.pointIn(px, py, self.x, self.y, self.w, self.h)
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

--- brighter, with a stronger bloom, while hovered
function IconLink:draw()
    Marks.draw(self.mark, self.x, self.y, self.w,
        self.hover and HOVER_COLOR or Theme.colors.textDim,
        self.hover and HOVER_GLOW or IDLE_GLOW)
end

return IconLink
