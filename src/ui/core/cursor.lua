-- The game's cursor, everywhere: a small dot, white at rest, that eases to
-- the theme's accent color over something interactive, or danger red over
-- something destructive (Quit, Discard). Replaces the OS arrow app-wide.
--
--   UI.Cursor.init()          -- once, at boot (main.lua)
--   UI.Cursor.update(dt)      -- once a frame, before draw
--   UI.Cursor.draw()          -- once a frame, last -- always on top
--
-- A screen reports hover state via FocusGroup:hovering's second return
-- (Menu/Dialog forward to it), whether the hovered widget is `danger = true`:
--
--   function State:draw()
--       local over, danger = self.menu:hovering(self.mouseX, self.mouseY)
--       UI.Cursor.setHover(self.mouseX and over, danger)
--   end
--
-- setHover must be called unconditionally every frame, not just when true --
-- there's no automatic reset, so a screen that only calls it inside `if
-- hovering then` leaves the dot stuck colored. Belongs in draw, not
-- mousemoved: mousemoved stops firing once the pointer holds still.

local Theme = require "ui.core.theme"
local Globals = require "globals";

local Cursor = {}

local RADIUS = Globals.cursor.size -- design-space px, see Theme.px

local WHITE = Globals.cursor.color

local hovering = false      -- the latest setHover request
local danger = false        -- true when the hovered thing is destructive
local current = { 1, 1, 1 } -- eased toward this frame's target color

function Cursor.init()
    love.mouse.setVisible(false)
end

function Cursor.setHover(isHovering, isDanger)
    hovering = isHovering
    danger = isDanger or false
end

-- eases at the same rate a focused widget's glow does, so the cursor reads
-- as part of the same UI. Each channel chases independently rather than
-- blending through one 0..1 mix, so hover-to-danger reads the same as rest-to-danger.
function Cursor.update(dt)
    local target = WHITE
    if hovering then
        target = danger and Theme.colors.danger or Theme.colors.accent
    end
    current[1] = Theme.approach(current[1], target[1], dt)
    current[2] = Theme.approach(current[2], target[2], dt)
    current[3] = Theme.approach(current[3], target[3], dt)
end

function Cursor.draw()
    local x, y = love.mouse.getPosition()
    local radius = Theme.px(RADIUS)

    love.graphics.setColor(current[1], current[2], current[3], 1)
    love.graphics.circle("fill", x, y, radius)

    -- dark outline so the dot still reads against a bright panel; same shadow tone UI.Label uses
    Theme.setColor(Theme.colors.shadow)
    love.graphics.setLineWidth(math.max(1, Theme.px(1)))
    love.graphics.circle("line", x, y, radius)
    love.graphics.setLineWidth(1)

    love.graphics.setColor(1, 1, 1, 1)
end

return Cursor
