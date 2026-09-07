--- Quest types are data, the same way shops are -- no live world presence of
-- their own, just a spec an NPC's `quest` field names (see game/npcs.lua).
-- Every .lua file in game/quests/ returns one spec and is picked up at load:
--
--   -- game/quests/fetchScrap.lua
--   return { id = "fetchScrap",
--            objective = { type = "collect", item = "scrap", count = 10 },
--            reward = { xp = { skill = "foraging", amount = 50 }, currency = 20,
--                       items = { { id = "core", count = 1 } } } }
--
-- `objective.type` is a closed enum ("collect", "kill" today), not an
-- open-ended condition DSL -- a new type is a new case in checkObjective()
-- below plus new spec data, never new save-format work. A spec that fails to
-- load is skipped and logged rather than taking the game down with it.
--
-- Player progress lives in `save.quests[id] = { progress, complete }`
-- (states/play.lua mirrors this the same way it mirrors save.skills), not in
-- the spec. A quest with no entry there hasn't been accepted; `complete`
-- stays false until it's actually turned in, even after the objective is met
-- -- turning in is a deliberate step, not something that fires on its own.
--
-- "collect" is checked live against the current Inventory rather than a
-- persisted counter, so selling what you gathered before turning in genuinely
-- costs you the quest, the same way it would cost you the items -- there's no
-- other state to desync from. "kill" has no such live state once something's
-- dead, so it's the one type checkObjective() actually accumulates.

local Quests = {
    specs = {}, -- id -> spec
    ids = {},   -- sorted, so anything that lists quests doesn't depend on directory order
    loaded = false,
}

local DIR = "game/quests"
local MODULE = "game.quests."

--- requires one game/quests/<name>.lua and registers what it returns; a spec
-- that errors, isn't a table, has no string id, or collides with one already
-- registered is skipped and logged
---@param name string # module name without the .lua
local function loadSpec(name)
    local ok, spec = pcall(require, MODULE .. name)
    if not ok or type(spec) ~= "table" or type(spec.id) ~= "string" then
        print(("[quests] skipping '%s': %s"):format(name, tostring(spec)))
        return
    end
    if Quests.specs[spec.id] then
        print(("[quests] skipping '%s': id '%s' is already registered"):format(name, spec.id))
        return
    end
    Quests.specs[spec.id] = spec
    Quests.ids[#Quests.ids + 1] = spec.id
end

--- loads every spec in game/quests/ once; repeat calls are a no-op
function Quests.load()
    if Quests.loaded then return end
    Quests.loaded = true

    for _, file in ipairs(love.filesystem.getDirectoryItems(DIR)) do
        local name = file:match("^(.+)%.lua$")
        if name then loadSpec(name) end
    end
    table.sort(Quests.ids)
end

---@param id string
---@return table|nil spec
function Quests.get(id)
    return Quests.specs[id]
end

---@param quests table # save.quests: id -> { progress, complete }
---@param id string
---@return boolean # true once the player has taken this quest at all
function Quests.isAccepted(quests, id)
    return quests[id] ~= nil
end

---@param quests table
---@param id string
---@return boolean
function Quests.isComplete(quests, id)
    local entry = quests[id]
    return entry ~= nil and entry.complete == true
end

--- starts tracking a quest at zero progress; a quest already accepted (or
-- already turned in) is left untouched, so re-accepting can't roll it back
---@param quests table
---@param id string
function Quests.accept(quests, id)
    quests[id] = quests[id] or { progress = 0, complete = false }
end

---@param quests table
---@param id string
---@return integer # 0 for a quest that hasn't been accepted
function Quests.progressOf(quests, id)
    local entry = quests[id]
    return entry and entry.progress or 0
end

--- true once an accepted, not-yet-turned-in quest's objective is satisfied --
-- see the header for why "collect" reads live inventory instead of `progress`
---@param quests table
---@param inventory table # the player's Inventory
---@param id string
---@return boolean
function Quests.ready(quests, inventory, id)
    local spec = Quests.specs[id]
    local entry = quests[id]
    if not spec or not entry or entry.complete then return false end

    local objective = spec.objective
    if objective.type == "collect" then
        return inventory:count(objective.item) >= objective.count
    end
    return entry.progress >= objective.count
end

--- called from wherever the matching action happens (Play:collect, for both
-- types today) -- updates every accepted, not-yet-complete quest whose
-- objective matches `type` and `subject`. A quest that isn't accepted, or one
-- already turned in, is left alone.
---@param quests table
---@param type "collect"|"kill"
---@param subject string # an item id for "collect", an enemy spec id for "kill"
---@param amount number # "collect": the player's new total count of `subject`; "kill": how many just died (usually 1)
function Quests.checkObjective(quests, type, subject, amount)
    for id, entry in pairs(quests) do
        if not entry.complete then
            local spec = Quests.specs[id]
            local objective = spec and spec.objective
            if objective and objective.type == type then
                if type == "collect" and objective.item == subject then
                    entry.progress = math.max(entry.progress, math.min(amount, objective.count))
                elseif type == "kill" and (not objective.enemy or objective.enemy == subject) then
                    entry.progress = math.min(entry.progress + amount, objective.count)
                end
            end
        end
    end
end

--- marks a quest turned in; the caller is responsible for actually paying the
-- objective's cost and granting spec.reward first (see Play:turnInQuest) --
-- this only flips the flag once that's done
---@param quests table
---@param id string
function Quests.complete(quests, id)
    local entry = quests[id]
    if entry then entry.complete = true end
end

return Quests
