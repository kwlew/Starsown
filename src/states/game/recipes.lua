-- src/states/game/recipes.lua
-- Crafting recipes, matched against the crafting grid the way Minecraft does:
-- one item is spent from every occupied slot.
--
-- To add one, add a line at the bottom:
--   shaped("axe", 1, { "WW", "WS", " S" }, { W = "wood", S = "stone" })
--   shapeless("stone", 4, { "wood" })
-- A shaped pattern matches anywhere in the grid and mirrored left-to-right;
-- a space is an empty cell. Ids must exist in items.lua.

local Items = require "states.game.items"

local Recipes = { list = {}, GRID = 3 }

local function item(id)
    assert(Items.get(id), "recipe uses an unknown item: " .. tostring(id))
    return id
end

---@param result string
---@param count integer
---@param rows string[] # equal-length strings, at most GRID x GRID
---@param key table<string, string> # pattern letter -> item id
local function shaped(result, count, rows, key)
    local width, cells = #rows[1], {}
    assert(#rows <= Recipes.GRID and width <= Recipes.GRID, "recipe pattern is larger than the grid: " .. result)
    for _, row in ipairs(rows) do
        assert(#row == width, "recipe rows differ in length: " .. result)
        for c = 1, width do
            local letter = row:sub(c, c)
            cells[#cells + 1] = letter ~= " " and item(assert(key[letter], "no key for '" .. letter .. "': " .. result)) or false
        end
    end
    table.insert(Recipes.list, { result = item(result), count = count, width = width, height = #rows, cells = cells })
end

---@param result string
---@param count integer
---@param ingredients string[] # one id per item spent, order doesn't matter
local function shapeless(result, count, ingredients)
    assert(#ingredients <= Recipes.GRID * Recipes.GRID, "recipe has more ingredients than the grid has slots: " .. result)
    local sorted = {}
    for i, id in ipairs(ingredients) do sorted[i] = item(id) end
    table.sort(sorted)
    table.insert(Recipes.list, { result = item(result), count = count, shapeless = sorted })
end

shaped("axe", 1, { "WW", "WS", " S" }, { W = "wood", S = "stone" })
shaped("gem", 1, { " H ", "HSH", " H " }, { H = "herb", S = "stone" })
shapeless("planks", 4, { "wood" })

--- the occupied region of the grid, cropped to its bounding box
---@param ids table # grid slot -> item id (nil when empty), row-major
---@return integer? width
---@return integer? height
---@return table? cells # row-major, false where empty
local function crop(ids)
    local size = Recipes.GRID
    local minC, maxC, minR, maxR = size + 1, 0, size + 1, 0
    for i = 1, size * size do
        if ids[i] then
            local c, r = (i - 1) % size + 1, math.floor((i - 1) / size) + 1
            minC, maxC = math.min(minC, c), math.max(maxC, c)
            minR, maxR = math.min(minR, r), math.max(maxR, r)
        end
    end
    if maxC == 0 then return nil end

    local cells = {}
    for r = minR, maxR do
        for c = minC, maxC do cells[#cells + 1] = ids[(r - 1) * size + c] or false end
    end
    return maxC - minC + 1, maxR - minR + 1, cells
end

local function sameCells(recipe, cells, mirrored)
    local w = recipe.width
    for i, want in ipairs(recipe.cells) do
        local c = mirrored and w - (i - 1) % w or (i - 1) % w + 1
        if cells[math.floor((i - 1) / w) * w + c] ~= want then return false end
    end
    return true
end

--- The recipe the grid currently makes, if any.
---@param ids table # grid slot -> item id (nil when empty), row-major
---@return table? recipe
function Recipes.match(ids)
    local width, height, cells = crop(ids)
    if not cells then return nil end

    local present = {}
    for _, id in pairs(ids) do present[#present + 1] = id end
    table.sort(present)

    for _, recipe in ipairs(Recipes.list) do
        if recipe.shapeless then
            if #present == #recipe.shapeless then
                local same = true
                for i, id in ipairs(present) do same = same and id == recipe.shapeless[i] end
                if same then return recipe end
            end
        elseif recipe.width == width and recipe.height == height
            and (sameCells(recipe, cells, false) or sameCells(recipe, cells, true)) then
            return recipe
        end
    end
end

return Recipes
