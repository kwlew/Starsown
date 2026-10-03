--- A slow, tough melee hostile.

local Hostile = require("game.entities.hostile")

return Hostile:extend{
    name = "zombie",
    maxSpeed = 100,
    maxHealth = 8,
    aggroRange = 220,
    attackCooldown = 1.2,
    accel = 4,    -- shambles up to speed
    turnRate = 4,
    texture = "assets/textures/game/zombie.png",
}
