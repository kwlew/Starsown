-- src/states/game/items.lua
-- Item specs. `color` names a key in palette.items; display names come from
-- items.* in game.json so they translate.

local Items = {}

local specs = {
    wood  = { stack = 64, sides = 4, color = "wood" },
    stone = { stack = 64, sides = 6, color = "stone" },
    herb  = { stack = 16, sides = 3, color = "herb" },
    gem   = { stack = 8,  sides = 4, color = "gem", rotation = math.pi / 4 },
    axe   = { stack = 1,  sides = 3, color = "axe", tool = { kind = "axe", speed = 2.0 } },
}

for id, spec in pairs(specs) do spec.id = id end

---@param id string
---@return table? spec
function Items.get(id)
    return specs[id]
end

--- How fast the held item breaks something that wants `kind`. Bare hands, the
-- wrong tool and a non-tool all break at 1x; only a matching tool is faster.
---@param id string? # the held item, if any
---@param kind string? # the tool kind the target is broken with
---@return number multiplier
function Items.toolSpeed(id, kind)
    local tool = id and specs[id] and specs[id].tool
    if not tool or tool.kind ~= kind then return 1 end
    return tool.speed
end

return Items
