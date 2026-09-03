--- Owns the *live* enemies for a run: spawning, id assignment, iteration, and
-- applying damage by id rather than by the caller holding the enemy's own
-- table reference. `game/enemies.lua` is the type registry (specs + the
-- Enemy class); this is the instance list built from it.
--
--   local manager = EnemyManager.new()
--   local enemy = manager:spawnRandom(x, y)   -- enemy.id is now set
--   manager:damage(enemy.id, 3)               -- true if it found & hurt something
--
-- IDs are assigned per manager (so a fresh run starts back at 1) and mean
-- nothing beyond "which enemy" -- not derived from type or position. They
-- exist so anything that only knows an id (a saved target, a future ranged
-- attack, achievement tracking) can refer to one enemy without holding a
-- live reference that might already be dead and gone. `game/swipe.lua` is
-- the first thing that does this: it still finds targets by walking `list`
-- (it needs the geometry), but applies the hit through `damage(id, ...)`.

local Enemies = require "game.enemies"

local EnemyManager = {}
EnemyManager.__index = EnemyManager

---@return table
function EnemyManager.new()
    return setmetatable({
        list = {},  -- ordered; what update/draw/collision walk
        byId = {},  -- id -> enemy, for damage()/get()
        nextId = 1,
    }, EnemyManager)
end

--- assigns the enemy its id and files it; ids are per manager, so a fresh run
-- starts back at 1
---@param enemy Enemy
---@return Enemy enemy
function EnemyManager:add(enemy)
    enemy.id = self.nextId
    self.nextId = self.nextId + 1
    self.byId[enemy.id] = enemy
    self.list[#self.list + 1] = enemy
    return enemy
end

---@param id string # an enemy type
---@param x number
---@param y number
---@return Enemy|nil # nil if no spec goes by that id
function EnemyManager:spawn(id, x, y)
    local enemy = Enemies.spawn(id, x, y)
    return enemy and self:add(enemy)
end

---@param x number
---@param y number
---@return Enemy|nil # nil if no specs are loaded
function EnemyManager:spawnRandom(x, y)
    local enemy = Enemies.random(x, y)
    return enemy and self:add(enemy)
end

---@param id integer
---@return Enemy|nil
function EnemyManager:get(id)
    return self.byId[id]
end

---@return integer
function EnemyManager:count()
    return #self.list
end

--- the sanctioned way to hurt an enemy from outside: callers only need an id,
-- not a live reference, and get a clean false for one that's already gone
-- rather than an error
---@param id integer
---@param amount number
---@param knockX? number
---@param knockY? number
---@param knockZ? number
---@return boolean landed
function EnemyManager:damage(id, amount, knockX, knockY, knockZ)
    local enemy = self.byId[id]
    if not enemy then return false end
    return enemy:damage(amount, knockX, knockY, knockZ)
end

---@param dt number
---@param ctx table # passed through to each enemy
function EnemyManager:update(dt, ctx)
    for _, enemy in ipairs(self.list) do
        enemy:update(dt, ctx)
    end
end

--- removes anything dead or too far behind to matter; returns just the dead
-- ones (in removal order) so the caller can spawn loot/death particles --
-- a despawn is silent, nothing died
---@param player table
---@param despawnAt number # distance past which a live enemy is dropped
---@return Enemy[] died
function EnemyManager:prune(player, despawnAt)
    local died = {}
    for i = #self.list, 1, -1 do
        local enemy = self.list[i]
        if enemy.dead then
            died[#died + 1] = enemy
            self.byId[enemy.id] = nil
            table.remove(self.list, i)
        elseif player:distanceTo(enemy) > despawnAt then
            self.byId[enemy.id] = nil
            table.remove(self.list, i)
        end
    end
    return died
end

return EnemyManager
