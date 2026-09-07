--- Areas are data, the same way items/enemies/skills are -- but unlike those,
-- an area isn't a thing that gets spawned, it's a *place*: a ring of world
-- distance from the origin. There is one continuous World (see
-- game/world.lua); which area you're standing in is purely a function of
-- how far self.player is from (0, 0), never a separate instance to
-- teleport between. Every .lua file in game/areas/ returns one spec and is
-- picked up at load:
--
--   -- game/areas/wastes.lua
--   return { id = "wastes", radius = { min = 700, max = 1400 },
--            enemyTable = { "grunt" },
--            npcs = { { id = "scout", x = 0, y = -900 } } }
--
-- `radius` is required and must not overlap another area's -- Areas.at(x, y)
-- resolves whichever band a world point falls in. `ground`/`groundAlt`/
-- `groundLine` name keys in game/palette.lua (see game/world.lua) and are
-- all optional -- an area that omits them draws the same placeholder
-- checker every area used to share. `noSpawn` (also optional) skips
-- Play:spawnStep entirely for a point inside this band, the one thing
-- keeping the Hub (and the peaceful ring around it) safe. `enemyTable`
-- restricts Play:spawnStep's random pick to just those ids (see
-- Enemies.random) -- omitted, this band spawns from every registered enemy
-- type. `npcs` places NPCs at absolute world coordinates (there's only one
-- NpcManager now, built once from every area's list combined).
--
-- Display names are never in the spec; they come from assets/lang/*/areas.json
-- through I18n, so they translate like everything else. A spec that fails to
-- load is skipped and logged rather than taking the game down with it.

local I18n = require "core.i18n"
local Math = require "utils.math"

local Areas = {
    specs = {}, -- id -> spec
    ids = {},   -- sorted by radius.min ascending, so Areas.at can scan in distance order
    loaded = false,
}

local DIR = "game/areas"
local MODULE = "game.areas."

--- requires one game/areas/<name>.lua and registers what it returns; a spec
-- that errors, isn't a table, has no string id, or collides with one already
-- registered is skipped and logged
---@param name string # module name without the .lua
local function loadSpec(name)
    local ok, spec = pcall(require, MODULE .. name)
    if not ok or type(spec) ~= "table" or type(spec.id) ~= "string" then
        print(("[areas] skipping '%s': %s"):format(name, tostring(spec)))
        return
    end
    if Areas.specs[spec.id] then
        print(("[areas] skipping '%s': id '%s' is already registered"):format(name, spec.id))
        return
    end
    if type(spec.radius) ~= "table" or type(spec.radius.min) ~= "number" or type(spec.radius.max) ~= "number" then
        print(("[areas] skipping '%s': missing a { min, max } radius"):format(name))
        return
    end
    Areas.specs[spec.id] = spec
    Areas.ids[#Areas.ids + 1] = spec.id
end

--- loads every spec in game/areas/ once; repeat calls are a no-op
function Areas.load()
    if Areas.loaded then return end
    Areas.loaded = true

    for _, file in ipairs(love.filesystem.getDirectoryItems(DIR)) do
        local name = file:match("^(.+)%.lua$")
        if name then loadSpec(name) end
    end
    table.sort(Areas.ids, function(a, b) return Areas.specs[a].radius.min < Areas.specs[b].radius.min end)
end

---@param id string
---@return table|nil spec
function Areas.get(id)
    return Areas.specs[id]
end

--- the area whose radius band contains this world point, distance measured
-- from the origin (the Hub's own center). Falls back to the outermost
-- registered band rather than nil if the point is somehow past every
-- band's max (a gap in the authored radii) -- the same "degrade, don't
-- leave the world undefined" reasoning every other registry here already
-- follows for a bad/missing id.
---@param x number
---@param y number
---@return table spec
function Areas.at(x, y)
    local distance = Math.length(x, y)
    for _, id in ipairs(Areas.ids) do
        local spec = Areas.specs[id]
        if distance >= spec.radius.min and distance < spec.radius.max then
            return spec
        end
    end
    return Areas.specs[Areas.ids[#Areas.ids]] or {}
end

---@param id string
---@return string # the translated display name, never the raw id if a translation exists
function Areas.name(id)
    return I18n.t("areas." .. tostring(id))
end

return Areas
