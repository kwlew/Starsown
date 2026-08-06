-- tests/spec/audio_spec.lua -- lib/audio.lua
-- The channel mixer is pure Lua (LÖVE only ever sees the Sources), so it can be
-- driven with fake sources that record what was asked of them.
local Love = require "tests.helpers.love_stub"

local Audio

-- A stand-in for a love.audio Source, recording the state the mixer sets.
local function fakeSource()
    local source = { volume = 1, looping = false, playing = false, stopCount = 0 }
    function source:setVolume(value) self.volume = value end
    function source:getVolume() return self.volume end
    function source:setLooping(value) self.looping = value end
    function source:isLooping() return self.looping end
    function source:play() self.playing = true end
    function source:isPlaying() return self.playing end
    function source:stop()
        self.playing = false
        self.stopCount = self.stopCount + 1
    end
    return source
end

describe("audio", function()
    -- Channel volumes and the tracked-source list are module state, so every
    -- test gets a freshly required copy.
    beforeEach(function()
        Audio = Love.reload("lib.audio")
    end)

    describe("channel volume", function()
        it("starts every channel at full", function()
            assertEqual(Audio.getVolume("music"), 1.0)
            assertEqual(Audio.getVolume("sfx"), 1.0)
        end)

        it("keeps the channels independent", function()
            Audio.setVolume("music", 0.25)
            assertNear(Audio.getVolume("music"), 0.25)
            assertEqual(Audio.getVolume("sfx"), 1.0)
        end)

        it("rejects an unknown channel", function()
            assertError(function() Audio.setVolume("voice", 0.5) end, "unknown category")
            assertError(function() Audio.getVolume("voice") end, "unknown category")
        end)
    end)

    describe("play", function()
        it("applies the channel volume and starts the source", function()
            Audio.setVolume("sfx", 0.5)
            local source = fakeSource()
            Audio.play("sfx", source)
            assertNear(source.volume, 0.5)
            assertTrue(source.playing)
            assertFalse(source.looping)
        end)

        it("multiplies the per-play gain onto the channel volume", function()
            Audio.setVolume("sfx", 0.5)
            local source = fakeSource()
            Audio.play("sfx", source, { volume = 0.2 })
            assertNear(source.volume, 0.1)
        end)

        it("honours opts.loop", function()
            local source = fakeSource()
            Audio.play("music", source, { loop = true })
            assertTrue(source.looping)
        end)

        it("returns the source it played", function()
            local source = fakeSource()
            assertEqual(Audio.play("sfx", source), source)
        end)

        -- Preloading is best-effort: a clip that failed to load arrives as nil,
        -- and a missing sound must not take the game down mid-click.
        it("tolerates a nil source", function()
            assertNoError(function() Audio.play("sfx", nil) end)
            assertNil(Audio.play("sfx", nil))
        end)
    end)

    describe("live retuning", function()
        it("retunes sources that are already playing", function()
            local source = fakeSource()
            Audio.play("music", source)
            Audio.setVolume("music", 0.3)
            assertNear(source.volume, 0.3)
        end)

        -- The focus blip is played deliberately quiet; dragging the slider must
        -- keep it quiet relative to its channel rather than flattening it.
        it("preserves the per-play gain when retuning", function()
            local source = fakeSource()
            Audio.play("sfx", source, { volume = 0.2 })
            Audio.setVolume("sfx", 0.5)
            assertNear(source.volume, 0.1)
        end)

        it("leaves the other channel's sources alone", function()
            local music, sfx = fakeSource(), fakeSource()
            Audio.play("music", music)
            Audio.play("sfx", sfx)
            Audio.setVolume("music", 0.1)
            assertNear(music.volume, 0.1)
            assertNear(sfx.volume, 1.0)
        end)

        it("forgets sources that have finished", function()
            local finished = fakeSource()
            Audio.play("sfx", finished)
            finished.playing = false -- as if the clip ran out

            -- The next play prunes; after that, a volume change must not reach
            -- the finished source.
            Audio.play("sfx", fakeSource())
            finished.volume = -1
            Audio.setVolume("sfx", 0.5)
            assertEqual(finished.volume, -1, "a finished source was still being tracked")
        end)
    end)

    describe("stop", function()
        it("stops one source without touching the rest of the channel", function()
            local first, second = fakeSource(), fakeSource()
            Audio.play("sfx", first)
            Audio.play("sfx", second)

            Audio.stop("sfx", first)
            assertFalse(first.playing)
            assertTrue(second.playing)
        end)

        it("stops the whole channel when given no source", function()
            local first, second = fakeSource(), fakeSource()
            Audio.play("sfx", first)
            Audio.play("sfx", second)

            Audio.stop("sfx")
            assertFalse(first.playing)
            assertFalse(second.playing)
        end)

        it("drops stopped sources from tracking", function()
            local source = fakeSource()
            Audio.play("music", source)
            Audio.stop("music", source)

            source.volume = -1
            Audio.setVolume("music", 0.5)
            assertEqual(source.volume, -1, "a stopped source was still being tracked")
        end)

        it("stopAll clears every channel", function()
            local music, sfx = fakeSource(), fakeSource()
            Audio.play("music", music)
            Audio.play("sfx", sfx)

            Audio.stopAll()
            assertFalse(music.playing)
            assertFalse(sfx.playing)
        end)
    end)
end)
