--- Skill types are data, the same way items/enemies are. Every .lua file in
-- game/skills/ returns one spec and is picked up at load:
--
--   -- game/skills/combat.lua
--   return { id = "combat", curve = "standard",
--            curveParams = { base = 40, growth = 1.35 }, maxLevel = 50 }
--
-- A spec that fails to load is skipped and logged rather than taking the
-- game down with it. The planned skill list: Combat, Mining, Foraging,
-- Hunting, Enchanting, Alchemy, Carpentry, Fishing, Farming, Taming.
--
-- Level is never stored -- only XP is (save.skills[id] = { xp = n }), and
-- Skills.levelOf derives the level from it via the spec's curve each time
-- it's asked, the same "derived, never stored, so two things can't disagree"
-- principle Play:isPaused() uses for its own two pause flags.
--
-- Skills.meets(skills, requirement) is the one place anything -- an item, an
-- area, a quest -- checks a skill-level gate:
--
--   Items.specs.denseCore.requires = { skill = "combat", level = 2 }
--   if Skills.meets(self.skills, Items.get("denseCore").requires) then ... end
--
-- It never knows which chains exist; it only reads whatever requirement a
-- spec happens to carry, so a new gated item/area/quest is a data change,
-- never a new branch here. `skills` throughout this file is always a save's
-- own skills table (save.skills, or the Play screen's self.skills mirror of
-- it) -- an id -> { xp: number } map.

local I18n = require "core.i18n"

local Skills = {
    specs = {}, -- id -> spec
    ids = {},   -- sorted, so anything that lists skills doesn't depend on directory order
    loaded = false,
}

local DIR = "game/skills"
local MODULE = "game.skills."

--- named so a spec picks one by string rather than carrying a raw function --
-- unlike Enemies' optional behave (genuinely bespoke AI), a curve is pure
-- data-tuning: base/growth already give every skill its own pacing without
-- needing custom code per skill.
Skills.CURVES = {
    --- XP required to go from level n-1 to level n, not the running total
    standard = function(n, params)
        return (params.base or 40) * n ^ (params.growth or 1.35)
    end,
}

--- requires one game/skills/<name>.lua and registers what it returns; a spec
-- that errors, isn't a table, has no string id, or collides with one already
-- registered is skipped and logged
---@param name string # module name without the .lua
local function loadSpec(name)
    local ok, spec = pcall(require, MODULE .. name)
    if not ok or type(spec) ~= "table" or type(spec.id) ~= "string" then
        print(("[skills] skipping '%s': %s"):format(name, tostring(spec)))
        return
    end
    if Skills.specs[spec.id] then
        print(("[skills] skipping '%s': id '%s' is already registered"):format(name, spec.id))
        return
    end
    Skills.specs[spec.id] = spec
    Skills.ids[#Skills.ids + 1] = spec.id
end

--- loads every spec in game/skills/ once; repeat calls are a no-op
function Skills.load()
    if Skills.loaded then return end
    Skills.loaded = true

    for _, file in ipairs(love.filesystem.getDirectoryItems(DIR)) do
        local name = file:match("^(.+)%.lua$")
        if name then loadSpec(name) end
    end
    table.sort(Skills.ids)
end

---@param id string
---@return table|nil spec
function Skills.get(id)
    return Skills.specs[id]
end

--- display names live in assets/lang/*/skills.json, never in the spec, the
-- same split game/items.lua uses for item names
---@param id string
---@return string # the translated name, or the raw id if there's no translation
function Skills.name(id)
    return I18n.t("skills." .. tostring(id))
end

--- the XP cost of going from level n-1 to level n, per the spec's own curve
---@param id string
---@param n integer
---@return number|nil # nil if the id or its curve isn't registered
function Skills.xpForLevel(id, n)
    local spec = Skills.specs[id]
    if not spec then return nil end
    local curve = Skills.CURVES[spec.curve]
    if not curve then return nil end
    return curve(n, spec.curveParams or {})
end

--- walks the curve from level 1, accumulating each level's cost, until the
-- running total exceeds the stored XP -- cheap at any level count this game
-- will reach, and avoids needing a closed-form inverse of the curve
---@param skills table|nil # save.skills: id -> { xp: number }
---@param id string
---@return integer # 0 for an unrecorded skill or one with no registered spec
function Skills.levelOf(skills, id)
    local spec = Skills.specs[id]
    if not spec then return 0 end

    local xp = (skills and skills[id] and skills[id].xp) or 0
    local maxLevel = spec.maxLevel or math.huge

    local level, spent = 0, 0
    while level < maxLevel do
        local cost = Skills.xpForLevel(id, level + 1)
        if not cost then break end
        spent = spent + cost
        if spent > xp then break end
        level = level + 1
    end
    return level
end

--- adds XP to a skill, creating its entry the first time; an id with no
-- registered spec still accumulates XP (it just never produces a level
-- above 0 via levelOf), so this never needs Skills.load() to have run first
---@param skills table # save.skills: id -> { xp: number }, mutated in place
---@param id string
---@param amount number|nil # ignored if nil or <= 0
function Skills.grantXp(skills, id, amount)
    if not skills or not amount or amount <= 0 then return end
    skills[id] = skills[id] or { xp = 0 }
    skills[id].xp = skills[id].xp + amount
end

--- true when `skills` clears `requirement`, or when there's nothing to clear
---@param skills table|nil # save.skills: id -> { xp: number }
---@param requirement table|nil # { skill: string, level: integer }, or nil for "no requirement"
---@return boolean
function Skills.meets(skills, requirement)
    if not requirement then return true end
    return Skills.levelOf(skills, requirement.skill) >= requirement.level
end

return Skills
