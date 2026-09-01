-- The baseline enemy: slow, walks straight at you, dies in three hits. It has
-- no behave() of its own, so it uses the registry's default chase.

return {
    id = "grunt",
    sides = 4,
    radius = 13,
    speed = 78,
    hp = 3,
    color = "hostile",
    drops = {
        { id = "scrap", min = 1, max = 3 },
        { id = "core", chance = 0.12 },
    },
}
