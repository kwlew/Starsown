-- src/states/game/recipes.lua
-- Crafting recipes.

local Items = require "states.game.items"
local Json = require "vendor.json"

local Recipes = { list = {}, errors = {}, GRID = 3 }

local DIR = "assets/recipes"

local function item(id)
    assert(type(id) == "string" and Items.get(id), "unknown item: " .. tostring(id))
    return id
end

---@param spec table
---@return table recipe
local function buildShaped(spec)
    local rows, key = spec.pattern, spec.key
    assert(type(rows) == "table" and #rows > 0, "pattern must be a non-empty array of strings")
    assert(type(key) == "table", "a pattern needs a \"key\" mapping its letters to item ids")
    assert(#rows <= Recipes.GRID, "pattern is taller than the grid")

    local width, cells = #tostring(rows[1]), {}
    assert(width <= Recipes.GRID, "pattern is wider than the grid")
    for _, row in ipairs(rows) do
        assert(type(row) == "string" and #row == width, "pattern rows must be strings of equal length")
        for c = 1, width do
            local letter = row:sub(c, c)
            cells[#cells + 1] = letter ~= " " and item(key[letter] or error("pattern letter '" .. letter .. "' has no key")) or false
        end
    end
    return { width = width, height = #rows, cells = cells }
end

---@param spec table
---@return table recipe
local function buildShapeless(spec)
    local list = spec.ingredients
    assert(type(list) == "table" and #list > 0, "ingredients must be a non-empty array")
    assert(#list <= Recipes.GRID * Recipes.GRID, "more ingredients than the grid has slots")

    local sorted = {}
    for i, id in ipairs(list) do sorted[i] = item(id) end
    table.sort(sorted)
    return { shapeless = sorted }
end

--- Validates one recipe spec and adds it. Errors (unknown item, ragged
-- pattern, ...) are raised for the caller to catch.
---@param spec table
function Recipes.add(spec)
    assert(type(spec) == "table", "a recipe must be an object")
    local count = spec.count or 1
    assert(type(count) == "number" and count >= 1 and count % 1 == 0, "count must be a whole number, at least 1")

    local recipe
    if spec.pattern then
        recipe = buildShaped(spec)
    elseif spec.ingredients then
        recipe = buildShapeless(spec)
    else
        error("needs a \"pattern\" or \"ingredients\"")
    end
    recipe.result, recipe.count = item(spec.result), count
    table.insert(Recipes.list, recipe)
end

local function skip(where, reason)
    local message = ("[recipes] skipping %s: %s"):format(where, reason)
    print(message)
    table.insert(Recipes.errors, message)
end

--- (Re)reads every recipe file. Runs once on require; call again to pick up edits.
function Recipes.load()
    Recipes.list, Recipes.errors = {}, {}

    local files = love.filesystem.getDirectoryItems(DIR)
    table.sort(files)
    for _, filename in ipairs(files) do
        if filename:match("%.json$") then
            local path = DIR .. "/" .. filename
            local ok, specs = pcall(function() return Json.decode(assert(love.filesystem.read(path))) end)
            if not ok or type(specs) ~= "table" then
                skip(path, ok and "expected an array of recipes" or tostring(specs))
            else
                for i, spec in ipairs(specs) do
                    local added, err = pcall(Recipes.add, spec)
                    if not added then
                        skip(("%s #%d (%s)"):format(path, i, type(spec) == "table" and tostring(spec.result) or "?"),
                            (tostring(err):gsub("^.-:%d+: ", "")))
                    end
                end
            end
        end
    end
end

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

Recipes.load()

return Recipes
