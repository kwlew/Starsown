-- src/states/game/effects.lua
-- World particle pools, owned by the engine rather than by whatever spawns
-- into them - a felled tree is dropped from its chunk the same frame its last
-- chips fly, so an effect living on the tree would blink out mid-air.

local Particles = require "particles"
local Palette = require "states.game.rendering.palette"
local Units = require "states.game.units"

local Effects = {}
Effects.__index = Effects

local CHIP_SPREAD = math.pi * 0.7 -- how wide the chips spray off the struck face
local LEAF_SPREAD = math.pi * 2

---@return table
function Effects.new()
    return setmetatable({
        chips = Particles.Burst.new{ -- wood, kicked out on every bite
            countMin = 4, countMax = 6,
            speedMin = 1.4, speedMax = 3.8,
            lifeMin = 0.3, lifeMax = 0.55,
            sizeMin = Units.px(2.5), sizeMax = Units.px(4.5),
            drag = 4, gravity = 11, additive = false, fade = 0.35,
        },
        debris = Particles.Burst.new{ -- the heavier shower when a stage finally gives
            countMin = 5, countMax = 8,
            speedMin = 1.8, speedMax = 4.8,
            lifeMin = 0.45, lifeMax = 0.85,
            sizeMin = Units.px(3), sizeMax = Units.px(5.5),
            drag = 3.5, gravity = 14, additive = false, fade = 0.35,
        },
        leaves = Particles.Burst.new{ -- torn off a canopy: slow, and they flutter down
            countMin = 4, countMax = 7,
            speedMin = 0.5, speedMax = 2.2,
            lifeMin = 0.8, lifeMax = 1.7,
            sizeMin = Units.px(3), sizeMax = Units.px(5.5),
            drag = 2.2, gravity = 2.2, additive = false, fade = 0.45,
        },
    }, Effects)
end

--- Chips off the struck face of something, thrown back toward the hit.
---@param x number # meters
---@param y number
---@param angle number # radians, away from the body toward whoever struck it
---@param color number[]
function Effects:chip(x, y, angle, color)
    self.chips:spawnCone(x, y, angle, CHIP_SPREAD, color)
end

--- The shower when a body breaks: two grades of its color, thrown from across
-- the body rather than from one point, so it reads as it coming apart.
---@param x number
---@param y number
---@param radius number # meters
---@param color number[]
---@param highlight number[]
function Effects:shatter(x, y, radius, color, highlight)
    for _, grade in ipairs { color, highlight } do
        for _ = 1, 2 do
            local angle, distance = math.random() * math.pi * 2, math.random() * radius
            self.debris:spawn(x + math.cos(angle) * distance, y + math.sin(angle) * distance, grade)
        end
    end
end

--- A canopy coming apart, at the height it was drawn.
---@param x number
---@param y number # already lifted to the canopy
---@param radius number # meters; leaves start spread across the crown, not at a point
function Effects:canopyBurst(x, y, radius)
    for _, color in ipairs { Palette.trees.leaves, Palette.trees.leavesHighlight } do
        for _ = 1, 2 do
            local angle, distance = math.random() * math.pi * 2, math.random() * radius
            self.leaves:spawnCone(x + math.cos(angle) * distance, y + math.sin(angle) * distance,
                angle, LEAF_SPREAD, color)
        end
    end
end

---@param dt number
function Effects:update(dt)
    self.chips:update(dt)
    self.debris:update(dt)
    self.leaves:update(dt)
end

--- Call inside the camera transform, last: chips off a trunk are under its own
-- canopy, and being hidden by the leaves is exactly the feedback they exist for.
function Effects:draw()
    self.chips:draw()
    self.debris:draw()
    self.leaves:draw()
end

return Effects
