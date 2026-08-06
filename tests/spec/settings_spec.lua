-- tests/spec/settings_spec.lua -- lib/settings.lua
-- The save file is player-editable and survives across versions, so loading is
-- meant to be unbreakable: junk, wrong types, values from an older build and a
-- syntactically broken file must all end at the defaults rather than in the
-- window-creation path. conf.lua feeds these values straight into love.conf, so
-- a bad one here is a game that never draws a frame.
local Love = require "tests.helpers.love_stub"

local Settings

-- Writes a settings file with the given body (a Lua chunk, as Settings.save
-- would have produced).
local function withFile(body)
    Love.install({ ["settings.lua"] = body })
    Settings = Love.reload("lib.settings")
end

local function withoutFile()
    Love.install({})
    Settings = Love.reload("lib.settings")
end

describe("settings", function()
    describe("load", function()
        it("returns the defaults when there is no file", function()
            withoutFile()
            assertDeepEqual(Settings.load(), Settings.defaults)
        end)

        it("does not hand back the defaults table itself", function()
            withoutFile()
            local settings = Settings.load()
            settings.volume = 0.1
            assertEqual(Settings.defaults.volume, 0.8, "load() aliased the defaults table")
        end)

        it("overlays saved values onto the defaults", function()
            withFile('return { volume = 0.25, res_x = 1920, res_y = 1080, language = "pt" }')
            local settings = Settings.load()
            assertNear(settings.volume, 0.25)
            assertEqual(settings.res_x, 1920)
            assertEqual(settings.res_y, 1080)
            assertEqual(settings.language, "pt")
            -- Untouched keys still come from the defaults.
            assertEqual(settings.theme, "default")
            assertNear(settings.musicVolume, 0.8)
        end)

        it("ignores keys that are not settings", function()
            withFile('return { volume = 0.5, cheatMode = true }')
            local settings = Settings.load()
            assertNil(settings.cheatMode)
        end)

        it("ignores values of the wrong type", function()
            withFile('return { volume = "loud", vsync = "on", shareStats = "yes" }')
            local settings = Settings.load()
            assertNear(settings.volume, 0.8)
            assertEqual(settings.vsync, 0)
            assertEqual(settings.shareStats, true)
        end)

        it("falls back to the defaults on a corrupt file", function()
            withFile("return { volume = ")
            assertDeepEqual(Settings.load(), Settings.defaults)
        end)

        it("falls back to the defaults when the file returns a non-table", function()
            withFile("return 42")
            assertDeepEqual(Settings.load(), Settings.defaults)
        end)

        it("falls back to the defaults when the chunk raises", function()
            withFile("error('boom')")
            assertDeepEqual(Settings.load(), Settings.defaults)
        end)
    end)

    describe("validation", function()
        it("accepts every offered msaa level", function()
            for _, samples in ipairs({ 0, 2, 4, 8, 16 }) do
                withFile(("return { msaa = %d }"):format(samples))
                assertEqual(Settings.load().msaa, samples)
            end
        end)

        -- An older build wrote the selector's *index* here rather than the
        -- sample count. A 6 reaching love.conf renders the whole window white,
        -- and then there is no way to reach Options and fix it.
        it("rejects an msaa level that is not on the list", function()
            withFile("return { msaa = 6 }")
            assertEqual(Settings.load().msaa, 4)
            withFile("return { msaa = -1 }")
            assertEqual(Settings.load().msaa, 4)
        end)

        it("accepts every window mode", function()
            for _, mode in ipairs({ "windowed", "borderless", "exclusive" }) do
                withFile(("return { windowMode = %q }"):format(mode))
                assertEqual(Settings.load().windowMode, mode)
            end
        end)

        it("rejects an unknown window mode", function()
            withFile('return { windowMode = "cinema" }')
            assertEqual(Settings.load().windowMode, "windowed")
        end)

        it("rejects an empty language or theme", function()
            withFile('return { language = "", theme = "" }')
            local settings = Settings.load()
            assertEqual(settings.language, "en")
            assertEqual(settings.theme, "default")
        end)

        -- Codes and theme names are only shape-checked here; I18n and UI.Theme
        -- own the authoritative lists and fall back at set time.
        it("passes unknown-but-plausible language and theme codes through", function()
            withFile('return { language = "de", theme = "carbon" }')
            local settings = Settings.load()
            assertEqual(settings.language, "de")
            assertEqual(settings.theme, "carbon")
        end)
    end)

    describe("migration", function()
        it("turns a pre-windowMode fullscreen flag into borderless", function()
            withFile("return { fullscreen = true }")
            assertEqual(Settings.load().windowMode, "borderless")
        end)

        it("leaves windowed alone when the old flag was false", function()
            withFile("return { fullscreen = false }")
            assertEqual(Settings.load().windowMode, "windowed")
        end)

        it("prefers windowMode when both are present", function()
            withFile('return { fullscreen = true, windowMode = "windowed" }')
            assertEqual(Settings.load().windowMode, "windowed")
        end)
    end)

    describe("save", function()
        it("round-trips through load", function()
            withoutFile()
            local settings = Settings.load()
            settings.volume = 0.42
            settings.windowMode = "exclusive"
            settings.msaa = 8
            settings.language = "es"
            settings.shareStats = false
            Settings.save(settings)

            Settings = Love.reload("lib.settings")
            local loaded = Settings.load()
            assertDeepEqual(loaded, settings)
        end)

        it("writes every key in a stable order", function()
            withoutFile()
            Settings.save(Settings.load())
            local written = Love.files["settings.lua"]

            local keys = {}
            for key in written:gmatch("\n%s*(%w+) =") do keys[#keys + 1] = key end

            local sorted = {}
            for _, key in ipairs(keys) do sorted[#sorted + 1] = key end
            table.sort(sorted)
            assertDeepEqual(keys, sorted, "keys are not written in sorted order")

            for key in pairs(Settings.defaults) do
                assertTrue(written:find(key, 1, true) ~= nil, "missing key in saved file: " .. key)
            end
        end)

        it("fills a missing value from the defaults rather than writing nil", function()
            withoutFile()
            Settings.save({ volume = 0.5 })
            assertTrue(Love.files["settings.lua"]:find('language = "en"', 1, true) ~= nil)
            assertFalse(Love.files["settings.lua"]:find("= nil") ~= nil, "wrote a nil value")
        end)
    end)

    describe("applyGraphics", function()
        beforeEach(withoutFile)

        it("does nothing when the window already matches", function()
            local settings = Settings.load()
            Settings.applyGraphics(settings)
            assertEqual(Love.setModeCalls, 0, "recreated the window for no reason")
        end)

        it("applies a new resolution", function()
            local settings = Settings.load()
            settings.res_x, settings.res_y = 1920, 1080
            Settings.applyGraphics(settings)

            assertEqual(Love.setModeCalls, 1)
            assertEqual(Love.mode.width, 1920)
            assertEqual(Love.mode.height, 1080)
        end)

        -- A bare setMode(w, h) resets every unspecified flag, which would
        -- silently drop msaa/highdpi from conf.lua.
        it("carries the unrelated window flags over", function()
            local settings = Settings.load()
            settings.res_x = 1600
            Settings.applyGraphics(settings)

            assertEqual(Love.mode.flags.msaa, 4)
            assertEqual(Love.mode.flags.highdpi, true)
            assertEqual(Love.mode.flags.resizable, false)
        end)

        -- Carrying over the x/y captured while fullscreen (0,0) would park the
        -- title bar off the top of the screen.
        it("drops the window position when returning to windowed", function()
            local settings = Settings.load()
            settings.res_x = 1600
            Settings.applyGraphics(settings)

            assertNil(Love.mode.flags.x)
            assertNil(Love.mode.flags.y)
        end)

        it("switches into borderless fullscreen", function()
            local settings = Settings.load()
            settings.windowMode = "borderless"
            Settings.applyGraphics(settings)

            assertEqual(Love.setModeCalls, 1)
            assertEqual(Love.mode.flags.fullscreen, true)
            assertEqual(Love.mode.flags.fullscreentype, "desktop")
        end)

        it("switches into exclusive fullscreen at the stored resolution", function()
            local settings = Settings.load()
            settings.windowMode = "exclusive"
            settings.res_x, settings.res_y = 1920, 1080
            Settings.applyGraphics(settings)

            assertEqual(Love.mode.flags.fullscreen, true)
            assertEqual(Love.mode.flags.fullscreentype, "exclusive")
            assertEqual(Love.mode.width, 1920)
        end)

        -- In borderless, getMode reports the desktop size, so the stored
        -- resolution must not be compared: it would recreate the window on
        -- every call, flickering forever.
        it("ignores the stored resolution while borderless", function()
            Love.mode.width, Love.mode.height = 2560, 1440
            Love.mode.flags.fullscreen = true
            Love.mode.flags.fullscreentype = "desktop"

            local settings = Settings.load()
            settings.windowMode = "borderless"
            settings.res_x, settings.res_y = 1280, 720
            Settings.applyGraphics(settings)

            assertEqual(Love.setModeCalls, 0, "recreated the window over a resolution it must ignore")
        end)

        it("applies a vsync change", function()
            local settings = Settings.load()
            settings.vsync = 1
            Settings.applyGraphics(settings)

            assertEqual(Love.setModeCalls, 1)
            assertEqual(Love.mode.flags.vsync, 1)
        end)

        -- A driver can grant fewer samples than were asked for. Storing the
        -- request rather than the reality means the comparison never settles.
        it("stores the msaa the driver actually granted", function()
            local realSetMode = love.window.setMode
            love.window.setMode = function(width, height, flags)
                flags.msaa = math.min(flags.msaa, 4) -- as a capped driver would
                return realSetMode(width, height, flags)
            end

            local settings = Settings.load()
            settings.msaa = 16
            Settings.applyGraphics(settings)

            assertEqual(settings.msaa, 4, "kept the requested msaa instead of the granted one")
        end)

        it("re-shows the cursor after a mode change", function()
            love.mouse.setVisible(false)
            local settings = Settings.load()
            settings.windowMode = "exclusive"
            Settings.applyGraphics(settings)

            assertTrue(love.mouse.isVisible())
        end)
    end)

    describe("apply", function()
        it("pushes the master volume into LÖVE and the rest into the mixer", function()
            withoutFile()
            local Audio = require "lib.audio"

            local settings = Settings.load()
            settings.volume, settings.musicVolume, settings.sfxVolume = 0.5, 0.25, 0.75
            Settings.apply(settings)

            assertNear(love.audio.getVolume(), 0.5)
            assertNear(Audio.getVolume("music"), 0.25)
            assertNear(Audio.getVolume("sfx"), 0.75)
        end)
    end)
end)
