-- Localization: loads assets/lang/*.json, exposes t(key). Missing key/language
-- falls back to English (or the key itself) so bad translation data can't crash the UI.
--
--   I18n.load()
--   I18n.setLanguage("pt")
--   I18n.t("menu.play")            -- "Jogar" (or "Play", or "menu.play")
--   I18n.available()               -- { {code="en", name="English"}, ... }

local Json = require "vendor.json"

local I18n = {}

I18n.LANG_DIR = "assets/lang"
I18n.FALLBACK = "en"

local catalogs = {} -- code -> flattened { ["menu.play"] = "Play", ... }
local names = {}    -- code -> native display name

local active = {}   -- flattened map for the current language
local fallback = {} -- English map, consulted for missing keys
I18n.current = I18n.FALLBACK

-- { menu = { play = "P" } } -> { ["menu.play"] = "P" }; the reserved
-- `language` metadata block and non-string leaves are skipped.
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

local function loadFile(filename)
    local contents = love.filesystem.read(I18n.LANG_DIR .. "/" .. filename)
    if not contents then return nil end

    local ok, data = pcall(Json.decode, contents)
    if not ok or type(data) ~= "table" then
        print(("[i18n] skipping '%s': %s"):format(filename, tostring(data)))
        return nil
    end

    local name = data.language and data.language.name
    local map = flatten(data, nil, {})
    map["language.name"] = nil
    map["language.code"] = nil
    return map, name
end

-- filename's basename is its language code (en.json -> "en")
function I18n.load()
    catalogs, names = {}, {}
    for _, filename in ipairs(love.filesystem.getDirectoryItems(I18n.LANG_DIR)) do
        local code = filename:match("^(.+)%.json$")
        if code then
            local map, name = loadFile(filename)
            if map then
                catalogs[code] = map
                names[code] = name or code
            end
        end
    end

    fallback = catalogs[I18n.FALLBACK] or {}
    I18n.setLanguage(I18n.current)
end

function I18n.has(code)
    return catalogs[code] ~= nil
end

function I18n.setLanguage(code)
    if not catalogs[code] then
        code = I18n.FALLBACK
    end
    I18n.current = code
    active = catalogs[code] or {}
end

-- params substitutes {name} placeholders, e.g. t("hud.wave", { n = 3 })
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

-- English first, then the rest alphabetically by code
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
