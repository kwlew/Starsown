-- tests/spec/locales_spec.lua -- src/assets/lang/*.json
-- The shipped locale data, checked as data. I18n is forgiving by design (a
-- broken file is skipped, a missing key falls back to English), which is
-- exactly why a broken file is invisible in-game until a player on that
-- language sees English text — or an empty button. This is the gate that makes
-- it visible instead.
local Json = require "lib.json"

local LANG_DIR = "src/assets/lang"
local LOCALES = { "en", "es", "pt" }
local FALLBACK = "en"

local function read(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local contents = file:read("*a")
    file:close()
    return contents
end

-- Same flattening I18n does: { menu = { play = "P" } } -> { ["menu.play"] = "P" }.
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

local function loadLocale(code)
    local contents = read(LANG_DIR .. "/" .. code .. ".json")
    assertTrue(contents ~= nil, "missing locale file: " .. code .. ".json")
    local ok, data = pcall(Json.decode, contents)
    assertTrue(ok, ("%s.json is not valid JSON: %s"):format(code, tostring(data)))
    return data, flatten(data, nil, {})
end

local function sortedKeys(map)
    local keys = {}
    for key in pairs(map) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

describe("locale files", function()
    local reference

    beforeEach(function()
        local _, flat = loadLocale(FALLBACK)
        reference = flat
    end)

    it("ships the reference locale with a usable number of keys", function()
        assertTrue(#sortedKeys(reference) > 0, "en.json has no translatable strings")
    end)

    for _, code in ipairs(LOCALES) do
        describe(code .. ".json", function()
            it("is valid JSON", function()
                loadLocale(code)
            end)

            it("declares its own code and native name", function()
                local data = loadLocale(code)
                assertTrue(type(data.language) == "table", "no `language` metadata block")
                assertEqual(data.language.code, code, "the declared code does not match the filename")
                assertTrue(type(data.language.name) == "string" and data.language.name ~= "",
                    "no native display name (the language selector shows this)")
            end)

            it("translates every key English has", function()
                local _, flat = loadLocale(code)
                local missing = {}
                for _, key in ipairs(sortedKeys(reference)) do
                    if flat[key] == nil then missing[#missing + 1] = key end
                end
                assertEqual(#missing, 0, "untranslated keys: " .. table.concat(missing, ", "))
            end)

            it("has no keys English does not", function()
                local _, flat = loadLocale(code)
                local extra = {}
                for _, key in ipairs(sortedKeys(flat)) do
                    if reference[key] == nil then extra[#extra + 1] = key end
                end
                assertEqual(#extra, 0, "keys not present in en.json (typo, or a stale key): "
                    .. table.concat(extra, ", "))
            end)

            it("has no empty strings", function()
                local _, flat = loadLocale(code)
                local empty = {}
                for _, key in ipairs(sortedKeys(flat)) do
                    if flat[key]:match("^%s*$") then empty[#empty + 1] = key end
                end
                assertEqual(#empty, 0, "blank translations: " .. table.concat(empty, ", "))
            end)

            -- t() substitutes {name} placeholders from the caller's params. A
            -- translation that renames or drops one renders a literal "{n}" to
            -- the player, and no test of the code itself can catch that.
            it("keeps the placeholders English uses", function()
                local _, flat = loadLocale(code)
                local mismatches = {}
                for _, key in ipairs(sortedKeys(reference)) do
                    local translated = flat[key]
                    if translated then
                        local wanted, got = {}, {}
                        for name in reference[key]:gmatch("{(%w+)}") do wanted[name] = true end
                        for name in translated:gmatch("{(%w+)}") do got[name] = true end
                        for name in pairs(wanted) do
                            if not got[name] then
                                mismatches[#mismatches + 1] = ("%s (missing {%s})"):format(key, name)
                            end
                        end
                        for name in pairs(got) do
                            if not wanted[name] then
                                mismatches[#mismatches + 1] = ("%s (unexpected {%s})"):format(key, name)
                            end
                        end
                    end
                end
                assertEqual(#mismatches, 0, table.concat(mismatches, ", "))
            end)
        end)
    end
end)
