--- Pollen drifting up off the grass in view, thickest over flower patches.
-- Ambient: none under reduced motion.

local Math = require("utils.math")
local Ground = require("game.ground")
local Shapes = require("particles.shapes")
local Tile = require("game.tile")
local UI = require("ui")

local Pollen = {}
Pollen.__index = Pollen

local MAX = 14
local SPAWN_INTERVAL = 0.3
local SPAWN_TRIES = 6 -- random cells checked for flowers per spawn
local BARE_CHANCE = 0.5 -- of settling for flowerless grass instead
local LIFE_MIN, LIFE_MAX = 4, 7
local FADE = 1          -- s fading in, and out
local WIND = { 4, 12 }  -- design px/s, drifting right
local RISE = { 3, 8 }   -- design px/s
local SWAY = 6          -- design px side to side
local SWAY_SPEED = { 0.8, 1.6 }
local TWINKLE_SPEED = { 2, 4 }
local SIZE = Tile.SIZE / Tile.ART -- one texel
local GLOW_SIZE = 7
local GLOW_ALPHA = 0.25
local COLOR = { 1, 0.95, 0.6 }

---@return table
function Pollen.new()
    return setmetatable({ motes = {}, timer = 0 }, Pollen)
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
    self.motes[#self.motes + 1] = {
        x = x, y = y, t = 0,
        life = Math.randRange(LIFE_MIN, LIFE_MAX),
        wind = Math.randRange(WIND[1], WIND[2]),
        rise = Math.randRange(RISE[1], RISE[2]),
        phase = Math.randAngle(),
        sway = Math.randRange(SWAY_SPEED[1], SWAY_SPEED[2]),
        twinkle = Math.randRange(TWINKLE_SPEED[1], TWINKLE_SPEED[2]),
    }
end

---@param dt number
---@param camera table
function Pollen:update(dt, camera)
    for i = #self.motes, 1, -1 do
        local m = self.motes[i]
        m.t = m.t + dt
        if m.t >= m.life then
            table.remove(self.motes, i)
        else
            m.x, m.y = m.x + m.wind * dt, m.y - m.rise * dt
        end
    end
    if UI.Motion.reduced then return end
    self.timer = self.timer + dt
    while self.timer >= SPAWN_INTERVAL do
        self.timer = self.timer - SPAWN_INTERVAL
        if #self.motes < MAX then self:spawn(camera) end
    end
end

---@param m table
---@return number # 0..1
local function opacity(m)
    local edge = math.min(1, m.t / FADE, (m.life - m.t) / FADE)
    return edge * (0.6 + 0.4 * math.sin(m.phase + m.t * m.twinkle))
end

--- inside the camera, over the world
function Pollen:draw()
    if #self.motes == 0 then return end
    local glow, dot = Shapes.glow(), Shapes.square()
    local gs = GLOW_SIZE / Shapes.SIZE
    love.graphics.push("all")
    love.graphics.scale(Tile.worldScale())
    love.graphics.setBlendMode("add")
    for _, m in ipairs(self.motes) do
        local x = m.x + math.sin(m.phase + m.t * m.sway) * SWAY
        local a = opacity(m)
        love.graphics.setColor(COLOR[1], COLOR[2], COLOR[3], a * GLOW_ALPHA)
        love.graphics.draw(glow, x, m.y, 0, gs, gs, Shapes.SIZE / 2, Shapes.SIZE / 2)
        love.graphics.setColor(COLOR[1], COLOR[2], COLOR[3], a)
        love.graphics.draw(dot, x, m.y, 0, SIZE, SIZE, 0.5, 0.5)
    end
    love.graphics.pop()
end

return Pollen
