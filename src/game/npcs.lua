--- NPC types are data, the same way items/enemies are. Every .lua file in
-- game/npcs/ returns one spec and is picked up at load, so a new NPC is a
-- new file:
--
--   -- game/npcs/blacksmith.lua
--   return { id = "blacksmith", sides = 4, radius = 14, color = "metal",
--            interaction = "shop", shop = "blacksmithWares" }
--
-- `color` names a key in game/palette.lua and `sides` a silhouette (see
-- game/shape.lua) -- the same placeholder-shape vocabulary items/enemies use
-- until there's art. `interaction` names what states/play.lua's interact key
-- opens ("shop" is the only one wired up so far -- see game/shopPanel.lua);
-- `shop` names a game/shops/*.lua id for that case. Display names are never
-- in the spec; they come from assets/lang/*/npcs.json through I18n, same as
-- items/areas.
--
-- A spec that fails to load is skipped and logged rather than taking the
-- game down with it.

local Entity = require "game.entity"
local Palette = require "game.palette"
local I18n = require "core.i18n"

local Npcs = {
    specs = {}, -- id -> spec
    ids = {},   -- sorted, so anything that lists NPCs doesn't depend on directory order
    loaded = false,
}

local DIR = "game/npcs"
local MODULE = "game.npcs."

local NOTICE_RANGE = 220 -- world units; the one bit of "life" a stationary body has (see Npc:update)

---@class Npc : Entity
---@field id integer assigned by game/npcManager.lua, not here
---@field spec table
local Npc = Entity.extend()
Npcs.Npc = Npc

--- builds one live NPC from a spec; `id` stays unset until a manager adopts it
---@param spec table # one of Npcs.specs
---@param x number
---@param y number
---@return Npc
function Npc.new(spec, x, y)
    local self = Entity.init(setmetatable({}, Npc), {
        x = x, y = y,
        radius = spec.radius,
        sides = spec.sides,
        color = Palette[spec.color] or Palette.outline,
    })
    ---@cast self Npc
    self.spec = spec
    return self
end

--- turns to face the player once they wander close, the one bit of life a
-- stationary body has -- mirrors Enemy:chase's angle calc without any of its
-- movement. Facing freezes wherever it last pointed once the player leaves
-- range again, rather than snapping back, the same way a person's head stays
-- turned after someone walks past.
---@param dt number
---@param ctx table # reads ctx.player
function Npc:update(dt, ctx)
    local distance, dx, dy = self:distanceTo(ctx.player)
    if distance > 0.001 and distance <= NOTICE_RANGE then
        self.facing = math.atan2(dy, dx)
    end
end

--- files the spec under its id and appends it to the id list
---@param spec table
local function register(spec)
    Npcs.specs[spec.id] = spec
    Npcs.ids[#Npcs.ids + 1] = spec.id
end

--- requires one game/npcs/<name>.lua and registers what it returns; a spec
-- that errors, isn't a table, has no string id, or collides with one already
-- registered is skipped and logged
---@param name string # module name without the .lua
local function loadSpec(name)
    local ok, spec = pcall(require, MODULE .. name)
    if not ok or type(spec) ~= "table" or type(spec.id) ~= "string" then
        print(("[npcs] skipping '%s': %s"):format(name, tostring(spec)))
        return
    end
    if Npcs.specs[spec.id] then
        print(("[npcs] skipping '%s': id '%s' is already registered"):format(name, spec.id))
        return
    end
    register(spec)
end

--- loads every spec in game/npcs/ once; repeat calls are a no-op
function Npcs.load()
    if Npcs.loaded then return end
    Npcs.loaded = true

    for _, file in ipairs(love.filesystem.getDirectoryItems(DIR)) do
        local name = file:match("^(.+)%.lua$")
        if name then loadSpec(name) end
    end
    table.sort(Npcs.ids)
end

---@param id string
---@return table|nil spec
function Npcs.get(id)
    return Npcs.specs[id]
end

---@param id string
---@return string # the translated display name, never the raw id if a translation exists
function Npcs.name(id)
    return I18n.t("npcs." .. tostring(id))
end

--- one NPC of the named type, or nil if no spec goes by that id
---@param id string
---@param x number
---@param y number
---@return Npc|nil
function Npcs.spawn(id, x, y)
    local spec = Npcs.specs[id]
    if not spec then return nil end
    return Npc.new(spec, x, y)
end

return Npcs
