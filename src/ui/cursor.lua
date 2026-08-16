-- src/ui/cursor.lua
-- The game's cursor, everywhere: a small dot, white at rest, that eases to
-- the active theme's accent color while over something interactive. Replaces
-- the OS arrow for the whole app, not just one screen.
--
--   UI.Cursor.init()          -- once, at boot (main.lua)
--   UI.Cursor.update(dt)      -- once a frame, before draw
--   UI.Cursor.draw()          -- once a frame, last — always on top
--
-- Any screen that knows it's over something clickable says so, once a frame:
--
--   function State:draw()
--       ...
--       UI.Cursor.setHover(self.mouseX and self.menu:hovering(self.mouseX, self.mouseY))
--   end
--
-- setHover has to be called unconditionally with the current true/false, not
-- only when true — the hover state persists between calls (there's no
-- automatic per-frame reset), so a screen that only ever calls it inside an
-- `if hovering then` guard would leave the dot stuck accent-colored the first
-- time it goes true and never told otherwise. And it belongs in draw, not
-- mousemoved: mousemoved stops firing the instant the pointer holds still, so
-- a request made there would freeze the last color the moment the player
-- stopped moving over a button.

local Theme = require "ui.theme"

local Cursor = {}

local RADIUS = 4 -- design-space px, see Theme.px

local WHITE = { 1, 1, 1 }

local hovering = false -- the latest setHover request
local mix = 0           -- 0 = resting white, 1 = full accent

-- Hides the OS arrow for good. Call once, at boot.
function Cursor.init()
    love.mouse.setVisible(false)
end

function Cursor.setHover(isHovering)
    hovering = isHovering
end

-- Eases toward the requested state at the same rate every focused widget's
-- glow does, so the cursor's reaction reads as part of the same UI rather
-- than its own thing.
function Cursor.update(dt)
    mix = Theme.approach(mix, hovering and 1 or 0, dt)
end

function Cursor.draw()
    local x, y = love.mouse.getPosition()
    local radius = Theme.px(RADIUS)
    local r, g, b = Theme.lerp(WHITE, Theme.colors.accent, mix)

    love.graphics.setColor(r, g, b, 1)
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
