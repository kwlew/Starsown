--- Translated text. Lookups fall back: language -> English -> key.

local Format = require("utils.format")
local Loader = require("core.i18n.loader")

local I18n = {}

I18n.LANG_DIR = "assets/lang"
I18n.FALLBACK = "en"
I18n.current = I18n.FALLBACK

local catalogs, names = {}, {}
local active, fallback = {}, {}

--- (re)reads every language, keeping the active one
function I18n.load()
    catalogs, names = Loader.loadAll(I18n.LANG_DIR)
    fallback = catalogs[I18n.FALLBACK] or {}
    I18n.setLanguage(I18n.current)
end

---@param code string
---@return boolean
function I18n.has(code)
    return catalogs[code] ~= nil
end

--- unknown codes fall back to English
---@param code string
function I18n.setLanguage(code)
    if not catalogs[code] then code = I18n.FALLBACK end
    I18n.current = code
    active = catalogs[code] or {}
end

---@param key string # dotted, e.g. "menu.play"
---@param params? table<string, any> # fills {name} placeholders
---@return string
function I18n.t(key, params)
    local text = active[key] or fallback[key] or key
    if not params then return text end
    return (text:gsub("{(%w+)}", function(name)
        local value = params[name]
        return value ~= nil and tostring(value) or ("{" .. name .. "}")
    end))
end

--- a JSON array's entries, in order
---@param prefix string
---@return string[]
function I18n.list(prefix)
    local list, i = {}, 1
    while true do
        local key = prefix .. "." .. i
        local value = active[key] or fallback[key]
        if not value then return list end
        list[i], i = value, i + 1
    end
end

--- a number grouped with this language's separator
---@param n number
---@return string
function I18n.number(n)
    return Format.group(n, I18n.t("format.thousands"))
end

---@return table[] # { code, name }, English first
function I18n.available()
    local list = {}
    for code, name in pairs(names) do list[#list + 1] = { code = code, name = name } end
    table.sort(list, function(a, b)
        if a.code == I18n.FALLBACK then return true end
        if b.code == I18n.FALLBACK then return false end
        return a.code < b.code
    end)
    return list
end

return I18n
