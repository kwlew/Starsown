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

    biomes = { -- debug map tint only, until biomes have a look of their own
        plains = { 0.85, 0.85, 0.35 },
        forest = { 0.25, 0.75, 0.35 },
        dappledForest = { 0.65, 0.35, 0.25 },
        denseForest = { 0.05, 0.35, 0.20 },
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
        stamina = { 0.40, 0.40, 0.90 },
        currency = { 0.78, 0.78, 0.0 },
    },

    items = {
        wood = { 0.62, 0.45, 0.28 },
        planks = { 0.72, 0.55, 0.38 },
        stone = { 0.62, 0.64, 0.68 },
        herb = { 0.45, 0.75, 0.42 },
        gem = { 0.42, 0.72, 0.92 },
        axe = { 0.74, 0.78, 0.84 },
    },

    trees = {
        trunk = { 0.40, 0.28, 0.18 },
        chip = { 0.66, 0.48, 0.28 }, -- fresh-cut inner wood: the particles a chop throws off
        chipPale = { 0.80, 0.65, 0.42 },
        stump = { 0.35, 0.25, 0.17 },
        leaves = { 0.14, 0.32, 0.17 },
        leavesHighlight = { 0.21, 0.44, 0.23 },
        leavesOutline = { 0.07, 0.18, 0.09 },
    },

    range = { 0.96, 0.92, 0.80 },

    gridLine = { 0.15, 0.27, 0.17 },
}