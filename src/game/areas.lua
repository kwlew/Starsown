--- Area types are data, the same way items/enemies/skills are. Every .lua
-- file in game/areas/ returns one spec and is picked up at load:
--
--   -- game/areas/hub.lua
--   return { id = "hub", ground = "hubGround", groundAlt = "hubGroundAlt",
--            groundLine = "hubGroundLine", noSpawn = true,
--            exit = { x = 220, y = 0, w = 70, h = 70,
--                     target = "wastes", spawnX = 0, spawnY = 0 } }
--
-- `ground`/`groundAlt`/`groundLine` name keys in game/palette.lua (see
-- game/world.lua) and are all optional -- an area that omits them draws the
-- same placeholder checker every area used to share. `noSpawn` (also
-- optional) is the one piece of the eventual per-area spawn-table system
-- (Phase 4) worth landing early: without it, Play:spawnStep would happily
-- spawn enemies inside a "safe" Hub. `exit` is a single hand-placed
-- rectangle (see states/play.lua) -- a real N-area transition system is
-- still to come; this is deliberately just enough for two areas to lead
-- into each other.
--
-- Display names are never in the spec; they come from assets/lang/*/areas.json
-- through I18n, so they translate like everything else. A spec that fails to
-- load is skipped and logged rather than taking the game down with it.

local I18n = require "core.i18n"

local Areas = {
    specs = {}, -- id -> spec
    ids = {},   -- sorted, so anything that lists areas doesn't depend on directory order
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
    table.sort(Areas.ids)
end

---@param id string
---@return table|nil spec
function Areas.get(id)
    return Areas.specs[id]
end

---@param id string
---@return string # the translated display name, never the raw id if a translation exists
function Areas.name(id)
    return I18n.t("areas." .. tostring(id))
end

return Areas
