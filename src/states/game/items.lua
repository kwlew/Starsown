-- src/states/game/items.lua
-- Item specs. `color`/`sides` are the placeholder polygon; `texture` is an
-- optional path to the item's image and replaces it wherever it loads. Display
-- names come from items.* in game.json so they translate.
--
-- To add an item with a texture, drop the .png in assets/items/ and add:
--   my_item = { stack = 1, color = "stone", texture = "assets/items/my_item.png" },

local Items = {}

local specs = {
    wood  = { stack = 64, sides = 4, color = "wood" },
    stick = { stack = 64, sides = 3, color = "wood", texture = "assets/textures/items/stick.png" },
    planks = { stack = 64, sides = 6, color = "planks" },
    stone = { stack = 64, sides = 6, color = "stone" },
    herb  = { stack = 16, sides = 3, color = "herb" },
    gem   = { stack = 8,  sides = 4, color = "gem", rotation = math.pi / 4 },
    axe   = { stack = 1,  sides = 3, color = "axe", tool = { kind = "axe", speed = 2.0 }, texture = "assets/textures/items/stone_axe.png" },
    stone_sword = { stack = 1, sides = 3, color = "axe", texture = "assets/textures/items/stone_sword.png" },
    stone_pickaxe = { stack = 1, sides = 3, color = "axe", texture = "assets/textures/items/stone_pickaxe.png" },
}

for id, spec in pairs(specs) do spec.id = id end

---@param id string
---@return table? spec
function Items.get(id)
    return specs[id]
end

--- An item's texture, loaded on first use with nearest filtering so the pixels
-- stay crisp. Nil when the item has none or the file won't load (the caller
-- draws the placeholder shape; the failure is logged once).
---@param spec table
---@return any image # a love Image, or nil
function Items.texture(spec)
    if spec.image == nil then
        spec.image = false
        if spec.texture then
            local ok, image = pcall(love.graphics.newImage, spec.texture)
            if ok then
                image:setFilter("nearest", "nearest")
                spec.image = image
            else
                print(("item '%s': can't load texture %s"):format(spec.id, spec.texture))
            end
        end
    end
    return spec.image or nil
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
