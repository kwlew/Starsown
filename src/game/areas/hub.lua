--- Home base: a slate plaza distinct from the wilderness, and no monsters
-- (noSpawn) -- the whole point of a hub. `bounds` keeps the camera from
-- wandering off the plaza the way it would further out -- comfortably
-- covers every NPC below with room to spare, small enough that most
-- screens show the whole plaza without the camera needing to move at all.
-- The world origin is its center; everything here is authored relative to
-- (0, 0) accordingly.
return {
    id = "hub",
    ground = "hubGround", groundAlt = "hubGroundAlt", groundLine = "hubGroundLine",
    radius = { min = 0, max = 300 },
    noSpawn = true,
    bounds = { w = 700, h = 500 },
    npcs = {
        { id = "blacksmith", x = -120, y = -60 },
        { id = "wanderer", x = 60, y = -100 },
        { id = "elder", x = -60, y = 90 },
        { id = "warden", x = 120, y = 60 },
    },
}
