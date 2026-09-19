-- src/states/game/items.lua
-- Item specs. `color` names a key in palette.items; display names come from
-- items.* in game.json so they translate.

local Items = {}

local specs = {
    wood  = { stack = 64, sides = 4, color = "wood" },
    stone = { stack = 64, sides = 6, color = "stone" },
    herb  = { stack = 16, sides = 3, color = "herb" },
    gem   = { stack = 8,  sides = 4, color = "gem", rotation = math.pi / 4 },
}

for id, spec in pairs(specs) do spec.id = id end

---@param id string
---@return table? spec
function Items.get(id)
    return specs[id]
end

return Items
