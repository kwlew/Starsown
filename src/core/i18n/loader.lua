--- Reads every language folder's JSON files into flat catalogs.

local Json = require("lib.json")

local Loader = {}

--- nested tables to dotted keys; arrays become key.1, key.2
---@param tree table
---@param prefix string|nil
---@param out table<string, string>
---@return table<string, string>
local function flatten(tree, prefix, out)
    for key, value in pairs(tree) do
        local path = prefix and (prefix .. "." .. key) or tostring(key)
        if type(value) == "table" then
            flatten(value, path, out)
        elseif type(value) == "string" then
            out[path] = value
        end
    end
    return out
end

--- a bad file costs only its own keys
---@param path string
---@return table|nil
local function decodeFile(path)
    local contents = love.filesystem.read(path)
    if not contents then return nil end
    local ok, data = pcall(Json.decode, contents)
    if ok and type(data) == "table" then return data end
    print(("[i18n] skipping '%s': %s"):format(path, tostring(data)))
end

---@param dir string
---@return table<string, string> catalog
---@return string|nil displayName
local function loadLanguage(dir)
    local catalog, name = {}, nil
    for _, file in ipairs(love.filesystem.getDirectoryItems(dir)) do
        if file:match("%.json$") then
            local data = decodeFile(dir .. "/" .. file)
            if data then
                if file == "_meta.json" then name = data.language and data.language.name end
                flatten(data, nil, catalog)
            end
        end
    end
    catalog["language.name"], catalog["language.code"] = nil, nil
    return catalog, name
end

---@param root string # e.g. "assets/lang"
---@return table<string, table> catalogs # code -> catalog
---@return table<string, string> names # code -> display name
function Loader.loadAll(root)
    local catalogs, names = {}, {}
    for _, code in ipairs(love.filesystem.getDirectoryItems(root)) do
        local dir = root .. "/" .. code
        local info = love.filesystem.getInfo(dir)
        if info and info.type == "directory" then
            local catalog, name = loadLanguage(dir)
            if next(catalog) then
                catalogs[code], names[code] = catalog, name or code
            end
        end
    end
    return catalogs, names
end

return Loader
