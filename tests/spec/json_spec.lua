-- tests/spec/json_spec.lua -- lib/json.lua
-- The decoder is the only thing standing between a hand-edited locale file and
-- the game, so the malformed-input cases matter as much as the happy path.
local Json = require "lib.json"

describe("json.decode", function()
    describe("scalars", function()
        it("decodes numbers", function()
            assertEqual(Json.decode("0"), 0)
            assertEqual(Json.decode("42"), 42)
            assertEqual(Json.decode("-7"), -7)
            assertNear(Json.decode("3.25"), 3.25)
            assertNear(Json.decode("1e3"), 1000)
            assertNear(Json.decode("-2.5e-2"), -0.025)
        end)

        it("decodes literals", function()
            assertEqual(Json.decode("true"), true)
            assertEqual(Json.decode("false"), false)
            assertNil(Json.decode("null"))
        end)

        it("decodes strings", function()
            assertEqual(Json.decode('"hello"'), "hello")
            assertEqual(Json.decode('""'), "")
        end)
    end)

    describe("strings", function()
        it("applies the escape set", function()
            assertEqual(Json.decode([["a\"b"]]), 'a"b')
            assertEqual(Json.decode([["a\\b"]]), "a\\b")
            assertEqual(Json.decode([["a\/b"]]), "a/b")
            assertEqual(Json.decode([["a\nb"]]), "a\nb")
            assertEqual(Json.decode([["a\tb"]]), "a\tb")
            assertEqual(Json.decode([["a\rb"]]), "a\rb")
            assertEqual(Json.decode([["a\bb"]]), "a\bb")
            assertEqual(Json.decode([["a\fb"]]), "a\fb")
        end)

        -- The locale files are UTF-8 and full of accented characters, so this
        -- is the path every non-English string takes.
        it("decodes \\u escapes as UTF-8", function()
            assertEqual(Json.decode('"\\u0041"'), "A")
            assertEqual(Json.decode('"\\u00e7"'), "\195\167")     -- c-cedilla, 2 bytes
            assertEqual(Json.decode('"\\u20ac"'), "\226\130\172") -- euro sign, 3 bytes
        end)

        it("combines surrogate pairs into one code point", function()
            -- U+1F600 (grinning face), which only fits in JSON as a surrogate pair.
            assertEqual(Json.decode('"\\ud83d\\ude00"'), "\240\159\152\128")
        end)

        it("passes raw UTF-8 through untouched", function()
            assertEqual(Json.decode('"configurações"'), "configurações")
        end)
    end)

    describe("containers", function()
        it("decodes a flat object", function()
            assertDeepEqual(Json.decode('{"a": 1, "b": "two", "c": true}'),
                { a = 1, b = "two", c = true })
        end)

        it("decodes a flat array", function()
            assertDeepEqual(Json.decode('[1, 2, 3]'), { 1, 2, 3 })
        end)

        it("decodes empty containers", function()
            assertDeepEqual(Json.decode("{}"), {})
            assertDeepEqual(Json.decode("[]"), {})
        end)

        it("nests to arbitrary depth", function()
            local data = Json.decode('{"menu": {"buttons": [{"label": "Play"}]}}')
            assertEqual(data.menu.buttons[1].label, "Play")
        end)

        it("ignores whitespace between tokens", function()
            assertDeepEqual(Json.decode('  {\n\t"a"  :\r\n [ 1 , 2 ]  }  '), { a = { 1, 2 } })
        end)
    end)

    describe("malformed input", function()
        it("rejects trailing content", function()
            assertError(function() Json.decode('{"a":1} junk') end, "trailing content")
        end)

        it("rejects an unterminated string", function()
            assertError(function() Json.decode('"oops') end, "unterminated string")
        end)

        it("rejects an unknown escape", function()
            assertError(function() Json.decode([["a\qb"]]) end, "bad escape")
        end)

        it("rejects a truncated \\u escape", function()
            assertError(function() Json.decode([["\u12"]]) end)
        end)

        it("rejects a missing separator", function()
            assertError(function() Json.decode('{"a":1 "b":2}') end)
            assertError(function() Json.decode('[1 2]') end)
        end)

        it("rejects an unquoted key", function()
            assertError(function() Json.decode('{a: 1}') end, "expected string key")
        end)

        it("rejects a non-string argument", function()
            assertError(function() Json.decode(nil) end, "expected a string")
            assertError(function() Json.decode(12) end, "expected a string")
        end)
    end)
end)
