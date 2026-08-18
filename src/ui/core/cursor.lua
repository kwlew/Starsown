-- src/ui/cursor.lua
-- The game's cursor, everywhere: a small dot, white at rest, that eases to
-- the active theme's accent color while over something interactive — or to
-- the theme's danger red while over something destructive (Quit, Discard).
-- Replaces the OS arrow for the whole app, not just one screen.
--
--   UI.Cursor.init()          -- once, at boot (main.lua)
--   UI.Cursor.update(dt)      -- once a frame, before draw
--   UI.Cursor.draw()          -- once a frame, last — always on top
--
-- Any screen that knows it's over something clickable says so, once a frame.
-- FocusGroup:hovering (and Menu/Dialog, which just forward to it) already
-- returns a second value for exactly this — whether the hovered widget is
-- marked `danger = true`:
--
--   function State:draw()
--       ...
--       local over, danger = self.menu:hovering(self.mouseX, self.mouseY)
--       UI.Cursor.setHover(self.mouseX and over, danger)
--   end
--
-- setHover has to be called unconditionally with the current true/false, not
-- only when true — the hover state persists between calls (there's no
-- automatic per-frame reset), so a screen that only ever calls it inside an
-- `if hovering then` guard would leave the dot stuck colored the first time
-- it goes true and never told otherwise. And it belongs in draw, not
-- mousemoved: mousemoved stops firing the instant the pointer holds still, so
-- a request made there would freeze the last color the moment the player
-- stopped moving over a button.

local Theme = require "ui.core.theme"
local Globals = require "globals";

local Cursor = {}

local RADIUS = Globals.cursor.size -- design-space px, see Theme.px

local WHITE = Globals.cursor.color

local hovering = false -- the latest setHover request
local danger = false    -- true when the hovered thing is destructive
local current = { 1, 1, 1 } -- eased toward this frame's target color

-- Hides the OS arrow for good. Call once, at boot.
function Cursor.init()
    love.mouse.setVisible(false)
end

function Cursor.setHover(isHovering, isDanger)
    hovering = isHovering
    danger = isDanger or false
end

-- Eases toward the requested color at the same rate every focused widget's
-- glow does, so the cursor's reaction reads as part of the same UI rather
-- than its own thing. Each channel chases independently rather than blending
-- through a single 0..1 mix, so a hover-to-danger swap (accent straight to
-- red, no white in between) reads the same as a rest-to-danger one.
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

    -- A dark outline, straddling the fill's edge, so the dot still reads
    -- against a bright panel or a lit path tile — the same shadow tone
    -- UI.Label uses to keep text legible over the board.
    Theme.setColor(Theme.colors.shadow)
    love.graphics.setLineWidth(math.max(1, Theme.px(1)))
    love.graphics.circle("line", x, y, radius)
    love.graphics.setLineWidth(1)

    love.graphics.setColor(1, 1, 1, 1)
end

return Cursor
