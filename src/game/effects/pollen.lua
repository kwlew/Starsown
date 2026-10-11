--- Pollen drifting up off the grass in view, thickest over flower patches.
-- Ambient: none under reduced motion.

local Ground = require("game.ground")
local Math = require("utils.math")
local Particles = require("particles")
local Tile = require("game.tile")
local UI = require("ui")

local Pollen = {}
Pollen.__index = Pollen

local MAX = 14
local SPAWN_INTERVAL = 0.3
local SPAWN_TRIES = 6 -- random cells checked for flowers per spawn
local BARE_CHANCE = 0.5 -- of settling for flowerless grass instead
local WIND = { 4, 12 }  -- design px/s, drifting right
local RISE = { 3, 8 }   -- design px/s
local COLOR = { 1, 0.95, 0.6 }
local TEXEL = Tile.SIZE / Tile.ART

local MOTES = {
    sizeMin = TEXEL / 2, sizeMax = TEXEL / 2, -- one texel
    speedMin = 0, speedMax = 0, -- carried by wind and rise alone
    lifeMin = 4, lifeMax = 7,
    drag = 0,
    fadeIn = 1,
    fade = 0.2,
    grow = 0,
    glow = 7 / TEXEL, -- a 7 px halo
    glowAlpha = 0.25,
    twinkle = 0.8,
    twinkleSpeedMin = 2, twinkleSpeedMax = 4,
    sway = 6,
    swaySpeedMin = 0.8, swaySpeedMax = 1.6,
    texture = "square",
}

---@return table
function Pollen.new()
    return setmetatable({ motes = Particles.Burst.new(MOTES), timer = 0 }, Pollen)
end

--- a random point in view, preferring flowering cells; or nil
---@param camera table
local function spawnSpot(camera)
    local vx, vy, vw, vh = camera:view()
    for _ = 1, SPAWN_TRIES do
        local x, y = vx + math.random() * vw, vy + math.random() * vh
        if Ground.flowerCount(math.floor(x / Tile.SIZE), math.floor(y / Tile.SIZE)) > 0 then return x, y end
    end
    if math.random() < BARE_CHANCE then return vx + math.random() * vw, vy + math.random() * vh end
end

---@param camera table
function Pollen:spawn(camera)
    local x, y = spawnSpot(camera)
    if not x then return end
    self.motes:emit(x, y, 0, COLOR, 1, Math.randRange(WIND[1], WIND[2]), -Math.randRange(RISE[1], RISE[2]))
end

---@param dt number
---@param camera table
function Pollen:update(dt, camera)
    self.motes:update(dt)
    if UI.Motion.reduced then return end
    self.timer = self.timer + dt
    while self.timer >= SPAWN_INTERVAL do
        self.timer = self.timer - SPAWN_INTERVAL
        if #self.motes.particles < MAX then self:spawn(camera) end
    end
end

--- inside the camera, over the world
function Pollen:draw()
    love.graphics.push("all")
    love.graphics.scale(Tile.worldScale())
    self.motes:draw()
    love.graphics.pop()
end

return Pollen
