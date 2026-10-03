--- Creatures that never attack; they wander, maybe flee.

local Behaviors = require("game.behaviors")
local Entity = require("game.entity")

local Passive = Entity:extend{
    name = "passive",
    kind = "passive",
    maxSpeed = 120,
    maxHealth = 4,
    fleeRange = nil, -- nil never flees
    fallbackColor = "success",
}

function Passive:think(dt, world)
    local threat = self.fleeRange and world:nearest(self.x, self.y, "player", self.fleeRange)
    if threat then Behaviors.flee(self, threat) else Behaviors.wander(self, dt) end
end

return Passive
