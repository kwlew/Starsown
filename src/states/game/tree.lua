---@diagnostic disable: duplicate-set-field
-- src/states/game/tree.lua
-- A choppable tree: a trunk (an Entity, so it takes hits/flashes/staggers
-- like anything else) plus a canopy drawn separately, in its own late pass,
-- so it can fade toward `fadeAlpha` as the player nears the trunk instead of
-- fully hiding them. Felling the standing stage turns it into a stump
-- (smaller, no canopy, its own hp) rather than removing the tree outright;
-- breaking the stump is what finally clears it.
--
-- What you can chop is the trunk you can't walk through, plus a little
-- forgiveness - never the tile it stands on, which would let you swing at bare
-- grass in the tile's corner and miss a trunk leaning over the tile's edge.

local Entity = require "states.game.kernel.entity"
local World = require "states.game.rendering.world"
local Palette = require "states.game.rendering.palette"
local Perspective = require "states.game.rendering.perspective"
local Math = require "utils.math"
local Units = require "states.game.units"

local Tree = Entity.extend()

local TRUNK_RADIUS = 0.42 -- meters
local STUMP_RADIUS = TRUNK_RADIUS * 1.15
local CANOPY_RADIUS = 1.1
local CANOPY_HEIGHT = 1.2 -- purely visual lift, via Perspective.lift; not a real Entity z
local CANOPY_ALPHA = 0.95
local CANOPY_FADE_ALPHA = 0.18 -- alpha directly over the trunk, so the player is never fully hidden
local CANOPY_RIM = 3 -- pixels, in the bake
local CANOPY_MSAA = 4

-- Leaf clumps, as multiples of the canopy radius, so the silhouette is lumpy
-- instead of one flat disc. Order doesn't matter: they bake opaque.
local CLUMPS = {
    { x =  0.00, y =  0.00, r = 0.82 },
    { x = -0.42, y = -0.30, r = 0.60 },
    { x =  0.44, y = -0.26, r = 0.56 },
    { x = -0.40, y =  0.30, r = 0.55 },
    { x =  0.38, y =  0.34, r = 0.52 },
    { x =  0.02, y = -0.52, r = 0.52 },
    { x = -0.02, y =  0.50, r = 0.48 },
}

local LIT_OFFSET_X, LIT_OFFSET_Y = -0.09, -0.12 -- where the light comes from, in radii
local LIT_SCALE = 0.70

local REGEN = 1.2
local HIT_INTERVAL = 0.22 -- seconds per bite; the bite scales with it, so this is feel, not speed

local HIT_SLACK = 0.22 -- meters of forgiveness around the trunk when aiming at it

-- shorter than a bite, so each one reads as its own hit instead of holding the
-- trunk lit the whole time you chop
local FLASH_TIME = 0.13
local FLASH_STRENGTH = 0.45

local SHAKE_TIME = 0.26
local SHAKE_FREQ = 34 -- radians/sec: a couple of fast oscillations per bite
local SHAKE_TRUNK = 0.055 -- meters of sway at the trunk...
local SHAKE_CANOPY = 0.16 -- ...and at the crown, which leans further for the same hit

-- `hp` is integrity in seconds of bare-handed breaking, since bare hands drain
-- it at 1/sec (see Items.toolSpeed); `tool` is the kind that drains it faster.
local SPECS = {
    oak = {
        standing = {
            hp = 5.5, tool = "axe",
            radius = TRUNK_RADIUS, sides = 8, color = "trunk",
            solid = TRUNK_RADIUS, -- what blocks movement is the trunk, never the canopy
            drops = { id = "wood", min = 3, max = 5 },
            canopy = {
                radius = CANOPY_RADIUS, height = CANOPY_HEIGHT,
                alpha = CANOPY_ALPHA, fadeAlpha = CANOPY_FADE_ALPHA, fadeRadius = CANOPY_RADIUS,
            },
        },
        stump = {
            hp = 7.5, tool = "axe",
            radius = STUMP_RADIUS, sides = 8, color = "stump",
            solid = STUMP_RADIUS,
            drops = { id = "wood", min = 1, max = 2 },
        },
    },
}

--- Bakes one species' canopy into a Canvas, the way particles/nebula.lua bakes
-- its clouds: the clumps overlap, so drawing them live at a faded alpha would
-- blend each overlap darker than the rest. One baked image fades evenly.
-- Baked in pixels at zoom 1 and drawn back down to meters.
---@param spec table # a canopy spec
---@diagnostic disable-next-line: undefined-doc-name
---@return love.canvas canvas
local function bakeCanopy(spec)
    local radius = spec.radius * Units.PPM
    local extent = 0
    for _, clump in ipairs(CLUMPS) do
        extent = math.max(extent, (Math.length(clump.x, clump.y) + clump.r) * radius)
    end

    local size = math.ceil((extent + CANOPY_RIM) * 2)
    local center = size / 2
    local msaa = math.min(CANOPY_MSAA, love.graphics.getSystemLimits().canvasmsaa)
    local canvas = love.graphics.newCanvas(size, size, { msaa = msaa })
    local previous = love.graphics.getCanvas()

    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.origin() -- the camera translate is live when this bakes
    love.graphics.clear(0, 0, 0, 0)

    -- rim as a larger fill under the body, so the clumps' seams never show as
    -- lines through the middle the way stroking each one would
    for _, pass in ipairs {
        { color = Palette.trees.leavesOutline, grow = CANOPY_RIM, scale = 1, ox = 0, oy = 0 },
        { color = Palette.trees.leaves, grow = 0, scale = 1, ox = 0, oy = 0 },
        { color = Palette.trees.leavesHighlight, grow = 0, scale = LIT_SCALE,
          ox = LIT_OFFSET_X, oy = LIT_OFFSET_Y },
    } do
        love.graphics.setColor(pass.color)
        for _, clump in ipairs(CLUMPS) do
            love.graphics.circle("fill",
                center + (clump.x + pass.ox) * radius,
                center + (clump.y + pass.oy) * radius,
                clump.r * radius * pass.scale + pass.grow)
        end
    end

    love.graphics.setCanvas(previous)
    love.graphics.pop()
    return canvas
end

---@param spec table? # { id, min, max }
---@return table? stack # { id, count }, shaped for Inventory:add/put
local function rollDrops(spec)
    if not spec then return nil end
    return { id = spec.id, count = Math.randInt(spec.min, spec.max) }
end

--- Trees are placed by tile, not by pixel: one tree owns one tile and stands
-- at its centre.
---@param col integer
---@param row integer
---@param species string? # defaults to "oak", the only one defined so far
---@return table
function Tree.new(col, row, species)
    species = species or "oak"
    local spec = SPECS[species].standing
    local x, y = World.tileCenter(col, row)
    local self = Entity.init(setmetatable({}, Tree), {
        x = x, y = y,
        radius = spec.radius, sides = spec.sides,
        color = Palette.trees[spec.color],
        hp = spec.hp,
        flashTime = FLASH_TIME, flashStrength = FLASH_STRENGTH,
    })
    self.col, self.row = col, row
    self.species = species
    self.stage = "standing"
    self.breaking = false
    self.breakTimer, self.breakAccum = 0, 0
    self.shake, self.shakeAngle = 0, 0
    return self
end

--- The trunk's grab radius: the footprint that blocks movement, plus enough
-- forgiveness that clipping its edge still lands the swing.
---@return number meters
function Tree:hitRadius()
    return self:stageSpec().solid + HIT_SLACK
end

--- How far the tree is leaning off its trunk right now, from the last bite.
---@param amplitude number # meters at full shake
---@return number dx
---@return number dy
function Tree:shakeOffset(amplitude)
    if self.shake <= 0 then return 0, 0 end
    local swing = math.sin(self.shake * SHAKE_FREQ) * amplitude * (self.shake / SHAKE_TIME)
    return math.cos(self.shakeAngle) * swing, math.sin(self.shakeAngle) * swing
end

---@return table
function Tree:stageSpec()
    return SPECS[self.species][self.stage]
end

---@return table?
function Tree:canopySpec()
    return self.stage == "standing" and SPECS[self.species].standing.canopy or nil
end

function Tree:becomeStump()
    local spec = SPECS[self.species].stump
    self.stage = "stump"
    self.radius, self.sides = spec.radius, spec.sides
    self.color = Palette.trees[spec.color]
    self.hp, self.maxHp = spec.hp, spec.hp
    self.hpFront, self.hpTrail, self.trailDelay = self.hp, self.hp, 0
    self.dead = false
end

---@param dt number
---@param ctx table # { speed: number, effects: table, fromX: number, fromY: number }
---@return table? drops # only on the frame a stage finishes
---@return boolean removed # true once the stump is gone and the caller should drop this tree
function Tree:breakWith(dt, ctx)
    self.breaking = true
    self.breakTimer = self.breakTimer + dt
    self.breakAccum = self.breakAccum + dt * ctx.speed
    if self.breakTimer < HIT_INTERVAL then return nil, false end
    self.breakTimer = self.breakTimer - HIT_INTERVAL

    local bite = self.breakAccum
    self.breakAccum = 0
    self:damage(bite)

    -- everything is thrown back the way the hit came from, off the struck face
    local away = math.atan2(ctx.fromY - self.y, ctx.fromX - self.x)
    self.shake, self.shakeAngle = SHAKE_TIME, away + math.pi
    local faceX, faceY = Math.polar(self.x, self:drawY(), away, self.radius)
    ctx.effects:chip(faceX, faceY, away, Palette.trees.chip)

    if not self.dead then return nil, false end

    local drops = rollDrops(self:stageSpec().drops)
    ctx.effects:shatter(self.x, self:drawY(), self.radius, Palette.trees.chip, Palette.trees.chipPale)

    local canopy = self:canopySpec()
    if canopy then
        ctx.effects:canopyBurst(self.x, self.y - Perspective.lift(canopy.height), canopy.radius * 0.7)
    end

    if self.stage == "standing" then
        self:becomeStump()
        return drops, false
    end
    return drops, true
end

--- Integrity recovers once you stop breaking, so a half-chopped tree left
-- alone goes back to whole rather than banking the progress forever.
---@param dt number
function Tree:update(dt)
    Entity.update(self, dt)
    self.shake = math.max(0, self.shake - dt)
    if self.breaking then
        self.breaking = false
    elseif self.hp < self.maxHp then
        self:heal(REGEN * dt)
    end
end

--- The trunk, leaning off its base for a moment after each bite. The shadow
-- (Entity:drawGround) is deliberately left where it is: the tree sways, its
-- footprint doesn't.
function Tree:draw()
    local dx, dy = self:shakeOffset(SHAKE_TRUNK)
    love.graphics.push()
    love.graphics.translate(dx, dy)
    Entity.draw(self)
    love.graphics.pop()
end

--- The ring showing what a swing would actually hit. Drawn on the ground under
-- the aimed tree, so the grab radius is something you can see rather than guess.
---@param strength number # 0..1, brightest while actually chopping
function Tree:drawHighlight(strength)
    local radius = self:hitRadius()
    love.graphics.setColor(Palette.range[1], Palette.range[2], Palette.range[3], 0.20 + 0.35 * strength)
    love.graphics.setLineWidth(Units.px(1.5))
    love.graphics.circle("line", self.x, self.y, radius, 40)
    love.graphics.setLineWidth(Units.LINE)
    love.graphics.setColor(1, 1, 1, 1)
end

--- How opaque the canopy should draw given the player's world position:
-- fully faded (fadeAlpha) directly over the trunk, easing out to full alpha
-- past fadeRadius.
---@param playerX number
---@param playerY number
---@return number
function Tree:canopyAlpha(playerX, playerY)
    local spec = self:canopySpec()
    if not spec then return 0 end

    local dist = Math.length(playerX - self.x, playerY - self.y)
    local t = Math.clamp01(dist / spec.fadeRadius)
    t = t * t * (3 - 2 * t) -- smoothstep, so the edge isn't a hard ring
    return spec.fadeAlpha + (spec.alpha - spec.fadeAlpha) * t
end

--- Draws the canopy, faded by the player's distance to the trunk. Meant to
-- be called in a late pass (after the player) so it can visually cover them
-- except where it's faded out - not part of Tree:draw()/Entity:draw().
---@param playerX number
---@param playerY number
function Tree:drawCanopy(playerX, playerY)
    local spec = self:canopySpec()
    if not spec then return end

    spec.canvas = spec.canvas or bakeCanopy(spec)

    local alpha = self:canopyAlpha(playerX, playerY)
    local dx, dy = self:shakeOffset(SHAKE_CANOPY)
    local y = self.y - Perspective.lift(spec.height) + dy
---@diagnostic disable-next-line: undefined-field
    local half = spec.canvas:getWidth() / 2

    -- the bake resolves to premultiplied alpha, so a plain alpha blend would
    -- ring the silhouette with dark edges as it fades
    love.graphics.setBlendMode("alpha", "premultiplied")
    love.graphics.setColor(alpha, alpha, alpha, alpha)
    love.graphics.draw(spec.canvas, self.x + dx, y, 0, Units.px(1), Units.px(1), half, half)
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(1, 1, 1, 1)
end

--- Pushes `entity` back out of this tree's footprint. The footprint is the
-- trunk (`solid`), not the canopy, so the leaves stay walkable-under.
---@param entity table
function Tree:collide(entity)
    local reach = self:stageSpec().solid + entity.radius
    local dx, dy = entity.x - self.x, entity.y - self.y
    local distance = Math.length(dx, dy)
    if distance >= reach then return end

    if distance == 0 then dx, dy, distance = 1, 0, 1 end -- dead centre: any direction will do
    local push = (reach - distance) / distance
    entity.x = entity.x + dx * push
    entity.y = entity.y + dy * push
end

return Tree
