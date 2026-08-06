-- lib/i18n.lua
-- Localization: loads per-language JSON files from assets/lang/, exposes a
-- t(key) lookup, and switches the active language live. Defensive like
-- lib/settings.lua — a missing/corrupt locale file is skipped rather than
-- fatal, a missing key returns the key itself, and an unknown language falls
-- back to English, so the UI can never crash on bad translation data.
--
--   I18n.load()                 -- once at boot; discovers every locale
--   I18n.setLanguage("pt")      -- swap the active language
--   I18n.t("menu.play")         -- -> "Jogar" (or "Play" fallback, or "menu.play")
--   I18n.available()            -- { {code="en", name="English"}, ... } for a selector

local Json = require "lib.json"

local I18n = {}

I18n.LANG_DIR = "assets/lang"
I18n.FALLBACK = "en"

-- code -> flattened { ["menu.play"] = "Play", ... }
local catalogs = {}
-- code -> native display name (from each file's `language.name`)
local names = {}

local active = {}   -- the flattened map for the current language
local fallback = {} -- the English map, consulted for missing keys
I18n.current = I18n.FALLBACK

-- Flattens a decoded JSON tree into dotted keys: { menu = { play = "P" } }
-- becomes { ["menu.play"] = "P" }. Non-string leaves are ignored (only text
-- is translatable); the reserved `language` metadata block is skipped.
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

-- Loads and flattens one locale file. Returns the flattened map and the
-- native display name, or nil on any failure (skipped by the caller).
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
    map["language.name"] = nil -- keep metadata out of the lookup table
    map["language.code"] = nil
    return map, name
end

-- Scans assets/lang/ for *.json and loads every locale it finds. The file's
-- basename is its language code (en.json -> "en").
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
    -- Make sure something is active even if setLanguage isn't called yet.
    I18n.setLanguage(I18n.current)
end

-- Is a locale available to switch to?
function I18n.has(code)
    return catalogs[code] ~= nil
end

-- Switches the active language. Unknown codes fall back to English so a stale
-- saved setting can never leave the game with no strings.
function I18n.setLanguage(code)
    if not catalogs[code] then
        code = I18n.FALLBACK
    end
    I18n.current = code
    active = catalogs[code] or {}
end

-- Looks up a key: active language, then English, then the key itself (so an
-- untranslated key is visible in-game rather than blank). `params` substitutes
-- {name} placeholders, e.g. t("hud.wave", { n = 3 }) on "Wave {n}".
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

-- Available locales for a language selector: { {code, name}, ... }, English
-- first, then the rest alphabetically by code for a stable order.
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
