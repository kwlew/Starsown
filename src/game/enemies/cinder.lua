--- The Ashlands' resident: quicker and hits harder than a grunt, but no
-- tougher -- the area is more dangerous through speed and damage, not a
-- bigger health bar. Weighted toward Power Cores rather than scrap, so the
-- area's own loot table feels like a step up, not just a reskin.
return {
    id = "cinder",
    sides = 3,
    radius = 12,
    speed = 112,
    hp = 3,
    damage = 2,
    color = "hostileAlt",
    drops = {
        { id = "core", min = 1, max = 2 },
        { id = "denseCore", chance = 0.5 }, -- gated by Skills.meets; see game/items/denseCore.lua
    },
}
