--- Home base: a slate plaza distinct from the wilderness, and no monsters
-- (noSpawn) -- the whole point of a hub. Its one exit leads to the Wastes.
return {
    id = "hub",
    ground = "hubGround", groundAlt = "hubGroundAlt", groundLine = "hubGroundLine",
    noSpawn = true,
    exit = { x = 220, y = 0, w = 70, h = 70, target = "wastes", spawnX = 0, spawnY = 0 },
    npcs = { { id = "blacksmith", x = -120, y = -60 } },
}
