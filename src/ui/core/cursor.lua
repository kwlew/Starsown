-- The game's cursor, everywhere: a small dot, white at rest, that eases to
-- the theme's accent color over something interactive, or danger red over
-- something destructive (Quit, Discard). Its outline thickens over anything
-- interactive too (a shape cue alongside the color one), and a thin ring
-- pulses out from it on every click. Replaces the OS arrow app-wide -- unless
-- the player has turned it off in Options (options.customCursor), in which
-- case the OS pointer shows instead and this draws nothing.
--
--   UI.Cursor.init()             -- once, at boot (main.lua)
--   UI.Cursor.setEnabled(bool)   -- once at boot with the saved setting, and
--                                   again whenever the Options toggle changes
--   UI.Cursor.update(dt)         -- once a frame, before draw
--   UI.Cursor.draw()             -- once a frame, last -- always on top
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
local Motion = require "ui.core.motion"
local Globals = require "globals";

local Cursor = {}

local RADIUS = Globals.cursor.size -- design-space px, see Theme.px

local WHITE = Globals.cursor.color

-- design-space px. The dot itself is tiny (RADIUS = 2), too small for a
-- hover scale-up to read at all -- the outline is already a big fraction of
-- its total size, so *that's* what carries the hover cue here, and it's
-- shape rather than color: a second signal alongside the accent shift, for
-- players who can't easily tell the accent hue apart from white.
local OUTLINE_WIDTH = 1
local HOVER_OUTLINE_WIDTH = 2

local CLICK_GROWTH = 5  -- design-space px the click ring expands by
local CLICK_LIFE = 0.25 -- seconds the click ring takes to fade out

local hovering = false      -- the latest setHover request
local danger = false        -- true when the hovered thing is destructive
local current = { 1, 1, 1 } -- eased toward this frame's target color
local enabled = true        -- whether the custom cursor draws at all
local outlineWidth = OUTLINE_WIDTH -- eased toward HOVER_OUTLINE_WIDTH while hovering
local wasDown = false        -- love.mouse.isDown(1) last frame, for edge detection
local click = nil            -- 0..CLICK_LIFE elapsed since the last click, or nil between clicks

function Cursor.init()
    Cursor.setEnabled(true) -- hidden by default until the saved setting overrides it
end

-- the OS pointer and this drawn one are never both visible: turning this
-- off has to show the system cursor again, not leave the player with none
function Cursor.setEnabled(isEnabled)
    enabled = isEnabled
    love.mouse.setVisible(not enabled)
end

function Cursor.setHover(isHovering, isDanger)
    hovering = isHovering
    danger = isDanger or false
end

-- eases at the same rate a focused widget's glow does, so the cursor reads
-- as part of the same UI. Each color channel chases independently rather
-- than blending through one 0..1 mix, so hover-to-danger reads the same as rest-to-danger.
function Cursor.update(dt)
    local target = WHITE
    if hovering then
        target = danger and Theme.colors.danger or Theme.colors.accent
    end
    current[1] = Theme.approach(current[1], target[1], dt)
    current[2] = Theme.approach(current[2], target[2], dt)
    current[3] = Theme.approach(current[3], target[3], dt)

    outlineWidth = Theme.approach(outlineWidth, hovering and HOVER_OUTLINE_WIDTH or OUTLINE_WIDTH, dt)

    -- click ring: snaps on with the press, not gradually, so even the
    -- fastest tap gets the full pulse rather than a partial one. Skipped
    -- under reduced motion -- unlike the outline width above (a one-time
    -- settle to a new resting state), an expanding ring is the kind of
    -- repeating pulse that setting exists to cut.
    local isDown = enabled and love.mouse.isDown(1)
    if isDown and not wasDown and not Motion.reduced then click = 0 end
    wasDown = isDown
    if click then
        click = click + dt
        if click >= CLICK_LIFE then click = nil end
    end
end

function Cursor.draw()
    if not enabled then return end

    local x, y = love.mouse.getPosition()
    local radius = Theme.px(RADIUS)

    -- starts flush with the dot's own edge and grows outward as it fades,
    -- in whatever color the cursor currently is
    if click then
        local t = click / CLICK_LIFE
        Theme.setColor(current, 1 - t)
        love.graphics.setLineWidth(math.max(1, Theme.px(OUTLINE_WIDTH)))
        love.graphics.circle("line", x, y, radius + Theme.px(CLICK_GROWTH) * t, 16)
    end

    love.graphics.setColor(current[1], current[2], current[3], 1)
    love.graphics.circle("fill", x, y, radius, 6)

    -- dark outline so the dot still reads against a bright panel; same shadow tone UI.Label uses
    Theme.setColor(Theme.colors.shadow)
    love.graphics.setLineWidth(math.max(1, Theme.px(outlineWidth)))
    love.graphics.circle("line", x, y, radius, 6)
    love.graphics.setLineWidth(1)

    love.graphics.setColor(1, 1, 1, 1)
end

return Cursor
