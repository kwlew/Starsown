--- F3 chords in a run: spawn, clear, hurt, heal, debug.

local Entities = require("game.entities")

local Commands = {}

local SPAWNS = { z = Entities.Zombie, x = Entities.Skeleton, p = Entities.Passive }

local ACTIONS = {
    h = function(engine) engine.player:damage(1) end,
    j = function(engine) engine.player:heal(1) end,
    g = function(engine) engine.showDebug = not engine.showDebug end,
    c = function(engine) engine.world:clear{ player = true } end,
}

--- F3+Z/X/P spawn at the view's edge
---@param engine table
---@param key string
function Commands.run(engine, key)
    local action = ACTIONS[key]
    if action then return action(engine) end
    local Type = SPAWNS[key]
    if Type then engine.world:spawn(Type, engine.camera:edgePoint()) end
end

return Commands
