-- Item types are data, the same way enemies are. Every .lua file in game/items/
-- returns one spec and is picked up at load, so a new item is a new file:
--
--   -- game/items/scrap.lua
--   return { id = "scrap", stack = 64, sides = 4, color = "metal" }
--
-- `color` names a key in game/palette.lua and `sides` a silhouette (see
-- game/shape.lua) -- between them that is the whole icon until there is art.
-- Display names are never in the spec; they come from assets/lang/*/items.json
-- through I18n, so they translate like everything else.

local Palette = require "game.palette"
local I18n = require "core.i18n"

local Items = {
    specs = {}, -- id -> spec
    ids = {},   -- sorted
    loaded = false,
}

local DIR = "game/items"
local MODULE = "game.items."
local DEFAULT_STACK = 64

local function loadSpec(name)
    local ok, spec = pcall(require, MODULE .. name)
    if not ok or type(spec) ~= "table" or type(spec.id) ~= "string" then
        print(("[items] skipping '%s': %s"):format(name, tostring(spec)))
        return
    end
    if Items.specs[spec.id] then
        print(("[items] skipping '%s': id '%s' is already registered"):format(name, spec.id))
        return
    end
    Items.specs[spec.id] = spec
    Items.ids[#Items.ids + 1] = spec.id
end

function Items.load()
    if Items.loaded then return end
    Items.loaded = true

    for _, file in ipairs(love.filesystem.getDirectoryItems(DIR)) do
        local name = file:match("^(.+)%.lua$")
        if name then loadSpec(name) end
    end
    table.sort(Items.ids)
end

function Items.get(id)
    return Items.specs[id]
end

-- how many of `id` fit in one slot; an unknown item stacks alone rather than
-- stacking to infinity, so a bad id can never swallow the whole inventory
function Items.stack(id)
    local spec = Items.specs[id]
    if not spec then return 1 end
    return spec.stack or DEFAULT_STACK
end

function Items.name(id)
    return I18n.t("items." .. tostring(id))
end

function Items.color(id)
    local spec = Items.specs[id]
    return (spec and Palette[spec.color]) or Palette.outline
end

function Items.sides(id)
    local spec = Items.specs[id]
    return spec and spec.sides
end

return Items
