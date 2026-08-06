-- tests/spec/i18n_spec.lua -- lib/i18n.lua
-- Locale data is the one part of the game that is expected to be incomplete
-- (a language lands before every key is translated), so the fallback chain is
-- the behaviour worth pinning down: active language, then English, then the key
-- itself. Nothing here may raise — a missing string must never be a crash.
local Love = require "tests.helpers.love_stub"

local I18n

local EN = [[{
    "language": { "code": "en", "name": "English" },
    "menu": { "play": "Play", "quit": "Quit", "onlyInEnglish": "Only here" },
    "hud": { "wave": "Wave {n}", "greet": "Hi {name}, wave {n}" }
}]]

local PT = [[{
    "language": { "code": "pt", "name": "Portugues" },
    "menu": { "play": "Jogar", "quit": "Sair" },
    "hud": { "wave": "Onda {n}" }
}]]

local ES = [[{
    "language": { "code": "es", "name": "Espanol" },
    "menu": { "play": "Jugar" }
}]]

-- Seeds assets/lang/ with the given code -> contents map and loads it.
local function withLocales(files)
    local seeded = {}
    for code, contents in pairs(files) do
        seeded["assets/lang/" .. code .. ".json"] = contents
    end
    Love.install(seeded)
    I18n = Love.reload("lib.i18n")
    I18n.load()
    return I18n
end

describe("i18n", function()
    beforeEach(function()
        withLocales({ en = EN, pt = PT, es = ES })
    end)

    describe("load", function()
        it("discovers every locale file", function()
            assertTrue(I18n.has("en"))
            assertTrue(I18n.has("pt"))
            assertTrue(I18n.has("es"))
            assertFalse(I18n.has("de"))
        end)

        it("starts on the fallback language", function()
            assertEqual(I18n.current, "en")
        end)

        it("skips a corrupt locale instead of failing", function()
            assertNoError(function()
                withLocales({ en = EN, pt = "{ this is not json" })
            end)
            assertTrue(I18n.has("en"))
            assertFalse(I18n.has("pt"), "a corrupt locale was loaded anyway")
        end)

        it("ignores non-json files in the locale directory", function()
            Love.install({
                ["assets/lang/en.json"] = EN,
                ["assets/lang/README.md"] = "not a locale",
            })
            I18n = Love.reload("lib.i18n")
            assertNoError(function() I18n.load() end)
            assertFalse(I18n.has("README"))
        end)

        it("survives having no locale files at all", function()
            Love.install({})
            I18n = Love.reload("lib.i18n")
            assertNoError(function() I18n.load() end)
            assertEqual(I18n.t("menu.play"), "menu.play")
        end)
    end)

    describe("lookup", function()
        it("flattens nested keys into dotted paths", function()
            assertEqual(I18n.t("menu.play"), "Play")
        end)

        it("returns the active language's string", function()
            I18n.setLanguage("pt")
            assertEqual(I18n.t("menu.play"), "Jogar")
        end)

        it("falls back to English for an untranslated key", function()
            I18n.setLanguage("es")
            assertEqual(I18n.t("menu.play"), "Jugar")
            assertEqual(I18n.t("menu.quit"), "Quit", "did not fall back to English")
        end)

        it("returns the key itself when nothing has it", function()
            assertEqual(I18n.t("menu.nothingHasThis"), "menu.nothingHasThis")
        end)

        it("keeps the language metadata out of the lookup table", function()
            assertEqual(I18n.t("language.name"), "language.name")
            assertEqual(I18n.t("language.code"), "language.code")
        end)
    end)

    describe("setLanguage", function()
        it("switches the active language", function()
            I18n.setLanguage("pt")
            assertEqual(I18n.current, "pt")
        end)

        -- A stale saved setting (a locale that shipped and was later removed)
        -- must not leave the game with no strings at all.
        it("falls back to English for an unknown code", function()
            I18n.setLanguage("de")
            assertEqual(I18n.current, "en")
            assertEqual(I18n.t("menu.play"), "Play")
        end)

        it("tolerates a nil code", function()
            assertNoError(function() I18n.setLanguage(nil) end)
            assertEqual(I18n.current, "en")
        end)
    end)

    describe("interpolation", function()
        it("substitutes named placeholders", function()
            assertEqual(I18n.t("hud.wave", { n = 3 }), "Wave 3")
        end)

        it("substitutes more than one", function()
            assertEqual(I18n.t("hud.greet", { name = "Ada", n = 2 }), "Hi Ada, wave 2")
        end)

        it("leaves a placeholder in place when the parameter is missing", function()
            assertEqual(I18n.t("hud.wave", {}), "Wave {n}")
        end)

        it("stringifies non-string values", function()
            assertEqual(I18n.t("hud.wave", { n = true }), "Wave true")
        end)

        it("leaves the text alone when no parameters are given", function()
            assertEqual(I18n.t("hud.wave"), "Wave {n}")
        end)
    end)

    describe("available", function()
        it("lists every loaded locale with its native name", function()
            local list = I18n.available()
            assertEqual(#list, 3)

            local names = {}
            for _, entry in ipairs(list) do names[entry.code] = entry.name end
            assertEqual(names.en, "English")
            assertEqual(names.pt, "Portugues")
            assertEqual(names.es, "Espanol")
        end)

        it("puts English first and sorts the rest by code", function()
            local list = I18n.available()
            assertEqual(list[1].code, "en")
            assertEqual(list[2].code, "es")
            assertEqual(list[3].code, "pt")
        end)
    end)
end)
