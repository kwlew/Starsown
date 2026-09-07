--- The open run: grunts, and the game's original placeholder checker --
-- now the Wastes' own ground rather than the only ground there was (it sets
-- none of ground/groundAlt/groundLine, so World falls back to the same
-- default it always drew). Its one exit leads back to the Hub.
return {
    id = "wastes",
    exit = { x = 220, y = 0, w = 70, h = 70, target = "hub", spawnX = 0, spawnY = 0 },
}
