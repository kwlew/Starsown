--- A small icon button that opens an external link (GitHub, Discord, ...) --
-- the main menu's corner marks. A Widget, so it can join the same FocusGroup
-- as the menu buttons: Tab reaches it and Enter opens the link.
--
--   local link = IconLink.new{ mark = "github", url = "https://...", label = "GitHub" }
--   link:setBounds(x, y, size, size)

local Marks = require("ui.icons.marks")
local Sfx = require("ui.core.sfx")
local Theme = require("ui.core.theme")
local Widget = require("ui.widgets.widget")

local IconLink = Widget.extend({})

local HOVER_COLOR = { 0.80, 0.80, 0.80 }
local HOVER_GLOW, IDLE_GLOW = 1, 0.45

---@param config table # Widget.new's fields, plus mark: string, url: string
---@return table
function IconLink.new(config)
    local self = Widget.new(IconLink, config)
    self.mark = config.mark -- a name in Marks
    self.url = config.url
    self.hover = false
    self.pressed = false
    return self
end

function IconLink:open()
    love.system.openURL(self.url)
end

function IconLink:mousemoved(px, py)
    self.hover = self:contains(px, py)
end

--- captures the press, so the link only opens on a release over it
---@return boolean captured
function IconLink:mousepressed(px, py, button)
    if button ~= 1 or not self:contains(px, py) then return false end
    self.pressed = true
    Sfx.press()
    return true
end

--- opens only on a full press+release on the mark, not a click that drags off
function IconLink:mousereleased(px, py, button)
    if button ~= 1 or not self.pressed then return end
    self.pressed = false
    if self:contains(px, py) then self:open() end
end

--- Enter on a keyboard-focused link
function IconLink:activate()
    Sfx.press()
    self:open()
end

--- brighter, with a stronger bloom, while hovered or keyboard-focused
function IconLink:draw()
    local lit = self.hover or self.focused
    Marks.draw(self.mark, self.x, self.y, self.w,
        lit and HOVER_COLOR or Theme.colors.textDim,
        lit and HOVER_GLOW or IDLE_GLOW)
end

return IconLink
