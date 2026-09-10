--- The open run: grunts, and the game's original placeholder checker --
-- now this band's own ground rather than the only ground there was (it
-- sets none of ground/groundAlt/groundLine, so World falls back to the
-- same default it always drew). Its own NPC (not every one belongs in the
-- Hub) sits well out from the Hub/wilderness ring below.
return {
    id = "wastes",
    radius = { min = 700, max = 1400 },
    enemyTable = { "grunt" },
    npcs = { { id = "scout", x = 0, y = -900 } },
}
