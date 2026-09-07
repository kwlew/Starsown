--- Shop types are data, the same way areas/items/enemies are. Every .lua
-- file in game/shops/ returns one spec and is picked up at load:
--
--   -- game/shops/blacksmithWares.lua
--   return { id = "blacksmithWares",
--            sell = { { id = "core", price = 5 }, { id = "scrap", price = 1 } },
--            buy  = { { id = "ironSword", price = 40 } } }
--
-- `sell` is what the shop will buy from the player, `buy` is what the player
-- can buy from the shop -- naming mirrors the player's own perspective in
-- each list, not the shop's. Unlike items/enemies/NPCs there's no live
-- instance here -- a shop has no presence in the world of its own, it's just
-- the listing an NPC's `shop` field names (see game/npcs.lua), so this is a
-- plain spec registry, the same shape game/areas.lua uses.
--
-- A spec that fails to load is skipped and logged rather than taking the
-- game down with it.

local Shops = {
    specs = {}, -- id -> spec
    ids = {},   -- sorted, so anything that lists shops doesn't depend on directory order
    loaded = false,
}

local DIR = "game/shops"
local MODULE = "game.shops."

--- requires one game/shops/<name>.lua and registers what it returns; a spec
-- that errors, isn't a table, has no string id, or collides with one already
-- registered is skipped and logged
---@param name string # module name without the .lua
local function loadSpec(name)
    local ok, spec = pcall(require, MODULE .. name)
    if not ok or type(spec) ~= "table" or type(spec.id) ~= "string" then
        print(("[shops] skipping '%s': %s"):format(name, tostring(spec)))
        return
    end
    if Shops.specs[spec.id] then
        print(("[shops] skipping '%s': id '%s' is already registered"):format(name, spec.id))
        return
    end
    Shops.specs[spec.id] = spec
    Shops.ids[#Shops.ids + 1] = spec.id
end

--- loads every spec in game/shops/ once; repeat calls are a no-op
function Shops.load()
    if Shops.loaded then return end
    Shops.loaded = true

    for _, file in ipairs(love.filesystem.getDirectoryItems(DIR)) do
        local name = file:match("^(.+)%.lua$")
        if name then loadSpec(name) end
    end
    table.sort(Shops.ids)
end

---@param id string
---@return table|nil spec
function Shops.get(id)
    return Shops.specs[id]
end

return Shops
