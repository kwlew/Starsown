--- Owns the *live* NPCs for an area: id assignment and iteration, the same
-- shape game/enemyManager.lua uses for enemies -- see that file's header for
-- why ids exist (a quest's "talk to the blacksmith" objective, or "which NPC
-- am I trading with," should hold an id, not a live reference). No damage()
-- here: nothing can hurt an NPC. Unlike EnemyManager, a fresh one is only
-- built on area entry, never on player death -- an NPC is furniture for the
-- area, not a hostile spawn.
--
--   local manager = NpcManager.new()
--   local npc = manager:spawn("blacksmith", x, y)   -- npc.id is now set
--   manager:get(npc.id)                             -- back by id, not a live reference

local Npcs = require "game.npcs"

local NpcManager = {}
NpcManager.__index = NpcManager

---@return table
function NpcManager.new()
    return setmetatable({
        list = {},  -- ordered; what draw walks
        byId = {},  -- id -> npc, for get()
        nextId = 1,
    }, NpcManager)
end

--- assigns the NPC its id and files it; ids are per manager, so a fresh area
-- starts back at 1
---@param npc Npc
---@return Npc npc
function NpcManager:add(npc)
    npc.id = self.nextId
    self.nextId = self.nextId + 1
    self.byId[npc.id] = npc
    self.list[#self.list + 1] = npc
    return npc
end

---@param id string # an NPC type
---@param x number
---@param y number
---@return Npc|nil # nil if no spec goes by that id
function NpcManager:spawn(id, x, y)
    local npc = Npcs.spawn(id, x, y)
    return npc and self:add(npc)
end

---@param id integer
---@return Npc|nil
function NpcManager:get(id)
    return self.byId[id]
end

---@return integer
function NpcManager:count()
    return #self.list
end

---@param dt number
---@param ctx table # passed through to each NPC (reads ctx.player -- see Npc:update)
function NpcManager:update(dt, ctx)
    for _, npc in ipairs(self.list) do
        npc:update(dt, ctx)
    end
end

return NpcManager
