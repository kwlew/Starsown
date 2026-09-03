--- Locatization code.
local Json = require "vendor.json"

local I18n = {}

I18n.LANG_DIR = "assets/lang"
I18n.FALLBACK = "en"

local catalogs = {}
local names = {}

local active = {}
local fallback = {}
I18n.current = I18n.FALLBACK

--- flattens a decoded JSON tree into dotted keys (menu.play). Arrays aren't
-- special-cased, so they come out numbered (menu.splashes.1, .2, ...) --
-- I18n.list reads those back.
---@param tree table
---@param prefix string|nil
---@param out table<string, string> # accumulator, returned
---@return table<string, string> out
local function flatten(tree, prefix, out)
    for key, value in pairs(tree) do
        local path = prefix and (prefix .. "." .. key) or key
        if type(value) == "table" then
            flatten(value, path, out)
        elseif type(value) == "string" then
            out[path] = value
        end
    end
    return out
end

--- one JSON file, or nil (logged) if it's missing or malformed -- a bad file
-- costs its own topic, not the whole language
---@param path string
---@return table|nil
local function decodeFile(path)
    local contents = love.filesystem.read(path)
    if not contents then return nil end

    local ok, data = pcall(Json.decode, contents)
    if not ok or type(data) ~= "table" then
        print(("[i18n] skipping '%s': %s"):format(path, tostring(data)))
        return nil
    end
    return data
end

--- merges every .json in a language's directory into one flat catalog, which
-- is why adding a topic file needs no change here
---@param code string # directory name under LANG_DIR
---@return table<string, string> catalog
---@return string|nil # the display name, from _meta.json only
local function loadLanguage(code)
    local dir = I18n.LANG_DIR .. "/" .. code
    local map, name = {}, nil

    for _, filename in ipairs(love.filesystem.getDirectoryItems(dir)) do
        if filename:match("%.json$") then
            local data = decodeFile(dir .. "/" .. filename)
            if data then
                if filename == "_meta.json" then
                    name = data.language and data.language.name
                end
                flatten(data, nil, map)
            end
        end
    end

    map["language.name"] = nil
    map["language.code"] = nil
    return map, name
end

--- (re)loads every language directory, then re-applies the active language
function I18n.load()
    catalogs, names = {}, {}
    for _, code in ipairs(love.filesystem.getDirectoryItems(I18n.LANG_DIR)) do
        local info = love.filesystem.getInfo(I18n.LANG_DIR .. "/" .. code)
        if info and info.type == "directory" then
            local map, name = loadLanguage(code)
            if next(map) then
                catalogs[code] = map
                names[code] = name or code
            end
        end
    end

    fallback = catalogs[I18n.FALLBACK] or {}
    I18n.setLanguage(I18n.current)
end

---@param code string
---@return boolean
function I18n.has(code)
    return catalogs[code] ~= nil
end

--- switches the active catalog, falling back to English for an unknown code
---@param code string
function I18n.setLanguage(code)
    if not catalogs[code] then
        code = I18n.FALLBACK
    end
    I18n.current = code
    active = catalogs[code] or {}
end

--- the lookup every screen draws through. Falls back key -> English -> the
-- key itself, so missing translation data can never blank the UI.
---@param key string # dotted, e.g. "menu.play"
---@param params? table<string, any> # substituted into {name} placeholders
---@return string
function I18n.t(key, params)
    local text = active[key] or fallback[key] or key
    if params then
        text = text:gsub("{(%w+)}", function(name)
            local v = params[name]
            return v ~= nil and tostring(v) or ("{" .. name .. "}")
        end)
    end
    return text
end

--- reads a flattened JSON array (prefix.1, prefix.2, ...) back out in order.
-- Checks the catalogs directly rather than going through t(), which returns
-- the key on a miss and would never end the loop.
---@param prefix string
---@return string[]
function I18n.list(prefix)
    local list = {}
    local i = 1
    while true do
        local key = prefix .. "." .. i
        local value = active[key] or fallback[key]
        if not value then break end
        list[#list + 1] = value
        i = i + 1
    end
    return list
end

--- every loaded language for the options selector, English first, then by code
---@return table[] # { code: string, name: string }[]
function I18n.available()
    local list = {}
    for code, name in pairs(names) do
        list[#list + 1] = { code = code, name = name }
    end
    table.sort(list, function(a, b)
        if a.code == I18n.FALLBACK then return true end
        if b.code == I18n.FALLBACK then return false end
        return a.code < b.code
    end)
    return list
end

return I18n
