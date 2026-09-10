--- The scorched outer band -- cinders instead of grunts, and its own warm
-- ground palette. No hard gate on entry (see PLAN.md's "Hard level-gating
-- on areas goes away" note) -- nothing stops you from walking this far out
-- early, the cinders just make it a bad idea. `max` is unbounded: this is
-- the outermost registered band, so anything past the Wastes resolves here
-- rather than falling off the edge of the authored world.
return {
    id = "ashlands",
    ground = "ashlandsGround", groundAlt = "ashlandsGroundAlt", groundLine = "ashlandsGroundLine",
    radius = { min = 1400, max = math.huge },
    enemyTable = { "cinder" },
}
