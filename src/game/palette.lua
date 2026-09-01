-- Colors for the things that live in the world, deliberately outside
-- ui/core/theme.lua. A theme is chrome, and there are twelve of them: under
-- "ruby" an enemy painted with Theme.colors.danger is a red shape on a
-- red-tinted floor and stops reading as an enemy. The grid behind them is
-- still themed -- it is backdrop, and backdrop is exactly what a theme is for.
--
-- Specs name a key here (see game/enemies.lua) rather than carrying literals,
-- so every hostile can be re-tuned in one place.

return {
    player  = { 0.36, 0.68, 1.00 },
    blade   = { 0.86, 0.95, 1.00 }, -- the swipe arc, its sparks, the facing tick
    hostile = { 0.95, 0.33, 0.32 },
    outline = { 0.92, 0.95, 1.00 },
    range   = { 0.72, 0.86, 1.00 }, -- the ring the cursor is tethered inside
    shadow  = { 0.03, 0.05, 0.03 }, -- what every body casts on the ground
    flash   = { 1.00, 0.98, 0.94 }, -- what a body lerps toward the instant it is hit
    health  = { 0.95, 0.33, 0.32 },
    healthTrack = { 0.09, 0.09, 0.12 },

    -- item material classes, named for what they look like rather than for any
    -- one item, so new items reuse them (see game/items.lua)
    metal  = { 0.74, 0.77, 0.83 },
    plant  = { 0.52, 0.78, 0.42 },
    energy = { 0.64, 0.50, 0.98 },

    -- the ground, until a grass texture replaces it (see game/world.lua)
    ground     = { 0.17, 0.24, 0.15 },
    groundAlt  = { 0.20, 0.28, 0.18 },
    groundLine = { 0.11, 0.16, 0.10 },
}
