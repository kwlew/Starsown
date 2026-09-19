-- src/states/game/rendering/palette.lua
-- Palette for the game.
-- Colors for blocks, background, etc.

return {
    entity = {
        Default = {
            color = { 0.82, 0.80, 0.74 },
            shadow = { 0.05, 0.09, 0.06 },
            outline = { 0.10, 0.14, 0.11 },
        },

        flash = { 1.00, 0.97, 0.90 },

        Player = {
            color = { 0.93, 0.78, 0.52 },
            shadow = { 0.05, 0.09, 0.06 },
        }
    },

    tiles = {
        Grass = { 0.24, 0.40, 0.25 },
        Grass2 = { 0.21, 0.36, 0.23 },
    },

    hp = {
        border = { 0.03, 0.05, 0.04 },
        back = { 0.06, 0.09, 0.07 },
        full = { 0.55, 0.78, 0.45 },
        trail = { 0.95, 0.80, 0.30 },
        low = { 0.86, 0.38, 0.32 },
    },

    hud = {
        hp = { 0.86, 0.36, 0.34 },
        staminaTrail = { 1.00, 1.00, 1.00 },
        stamina = { 0.40, 0.66, 0.90 },
        currency = { 0.68, 0.48, 0.90 },
    },

    items = {
        wood = { 0.62, 0.45, 0.28 },
        stone = { 0.62, 0.64, 0.68 },
        herb = { 0.45, 0.75, 0.42 },
        gem = { 0.42, 0.72, 0.92 },
    },

    range = { 0.96, 0.92, 0.80 },

    gridLine = { 0.15, 0.27, 0.17 },
}