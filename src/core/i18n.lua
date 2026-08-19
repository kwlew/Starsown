-- Localization: loads assets/lang/<code>/*.json, exposes t(key). Missing
-- key/language falls back to English (or the key itself) so bad translation
-- data can't crash the UI.
--
--   I18n.load()
--   I18n.setLanguage("pt")
--   I18n.t("menu.play")            -- "Jogar" (or "Play", or "menu.play")
--   I18n.available()               -- { {code="en", name="English"}, ... }
--
-- One directory per language (assets/lang/en/, es/, pt/), one file per
-- topic inside it (menu.json, options.json, ...) -- every .json file found
-- in a language's directory is merged into that language's catalog, so a
-- new topic is just a new file, no code change here. _meta.json is the one
-- place `language.name`/`language.code` live, so a topic file can never
-- accidentally shadow it.
--
--   assets/lang/en/_meta.json    -- { "language": { "name", "code" } }
--   assets/lang/en/menu.json     -- { "menu": { ... } }
--   assets/lang/en/options.json  -- { "options": { ... } }
--   ...

local Json = require "vendor.json"

local I18n = {}

I18n.LANG_DIR = "assets/lang"
I18n.FALLBACK = "en"

local catalogs = {} -- code -> flattened { ["menu.play"] = "Play", ... }
local names = {}    -- code -> native display name

local active = {}   -- flattened map for the current language
local fallback = {} -- English map, consulted for missing keys
I18n.current = I18n.FALLBACK

-- { menu = { play = "P" } } -> { ["menu.play"] = "P" }; non-string leaves
-- are skipped (a string array, like menu.splashes, flattens to numbered
-- keys instead -- see I18n.list).
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

-- Merges every *.json file under assets/lang/<code>/ into one flattened
-- catalog. A bad file is skipped (logged by decodeFile) rather than taking
-- the whole language down with it -- one broken topic file used to mean one
-- broken language, back when it was all a single file.
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

-- each subdirectory of assets/lang/ is one language, named by its code (en/, es/, ...)
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

-- Every value under a numbered prefix -- "menu.splashes.1", ".2", ... --
-- collected in order until one is missing. Checked directly against
-- active/fallback rather than through t(), since t() returns the key itself
-- on a miss and would never let the loop end.
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
