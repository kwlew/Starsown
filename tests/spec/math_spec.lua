-- tests/spec/math_spec.lua -- lib/utils/math.lua
local Math = require "lib.utils.math"

describe("utils.math", function()
    describe("clamp", function()
        it("passes a value already inside the range through", function()
            assertEqual(Math.clamp(5, 0, 10), 5)
        end)

        it("clamps to the bounds", function()
            assertEqual(Math.clamp(-3, 0, 10), 0)
            assertEqual(Math.clamp(42, 0, 10), 10)
            assertEqual(Math.clamp(0, 0, 10), 0)
            assertEqual(Math.clamp(10, 0, 10), 10)
        end)

        -- Selector:valueColumnWidth relies on this: a row too narrow for its
        -- value column computes max < min and must collapse to min, not stay
        -- negative. See the comment on Math.clamp.
        it("yields min when max is below min", function()
            assertEqual(Math.clamp(-20, 0, -5), 0)
        end)

        it("clamp01 pins to the unit range", function()
            assertEqual(Math.clamp01(-0.5), 0)
            assertEqual(Math.clamp01(1.5), 1)
            assertNear(Math.clamp01(0.25), 0.25)
        end)
    end)

    describe("round", function()
        it("rounds halves up", function()
            assertEqual(Math.round(0.5), 1)
            assertEqual(Math.round(1.5), 2)
            assertEqual(Math.round(2.4), 2)
            assertEqual(Math.round(7), 7)
        end)
    end)

    describe("length", function()
        it("is the euclidean distance from the origin", function()
            assertNear(Math.length(3, 4), 5)
            assertNear(Math.length(0, 0), 0)
            assertNear(Math.length(-3, -4), 5)
        end)
    end)

    describe("wrapIndex", function()
        it("leaves in-range indices alone", function()
            assertEqual(Math.wrapIndex(1, 4), 1)
            assertEqual(Math.wrapIndex(4, 4), 4)
        end)

        it("wraps past either end", function()
            assertEqual(Math.wrapIndex(5, 4), 1)
            assertEqual(Math.wrapIndex(0, 4), 4)
            assertEqual(Math.wrapIndex(-1, 4), 3)
        end)

        it("collapses to 1 for a single-item list", function()
            assertEqual(Math.wrapIndex(0, 1), 1)
            assertEqual(Math.wrapIndex(9, 1), 1)
        end)
    end)

    describe("random helpers", function()
        -- Seeded, so a failure here is reproducible rather than a one-in-a-run
        -- mystery that vanishes on re-run.
        beforeEach(function() math.randomseed(20260806) end)

        it("randRange stays within its bounds", function()
            for _ = 1, 500 do
                local value = Math.randRange(-2, 7)
                assertTrue(value >= -2 and value <= 7, "randRange out of range: " .. value)
            end
        end)

        it("randInt returns integers and can reach both ends", function()
            local seenMin, seenMax = false, false
            for _ = 1, 500 do
                local value = Math.randInt(1, 3)
                assertEqual(value, math.floor(value), "randInt returned a non-integer")
                assertTrue(value >= 1 and value <= 3, "randInt out of range: " .. value)
                if value == 1 then seenMin = true end
                if value == 3 then seenMax = true end
            end
            assertTrue(seenMin, "randInt never returned its minimum")
            assertTrue(seenMax, "randInt never returned its maximum (the inclusive upper bound)")
        end)

        it("randAngle covers a full turn", function()
            for _ = 1, 200 do
                local angle = Math.randAngle()
                assertTrue(angle >= 0 and angle < math.pi * 2, "angle out of range: " .. angle)
            end
        end)
    end)
end)
