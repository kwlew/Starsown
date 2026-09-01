-- Enemy types are data. Every .lua file in game/enemies/ returns one spec and
-- is picked up at load, the way i18n picks up a language's topic files -- so a
-- new enemy is a new file and no change here:
--
--   -- game/enemies/darter.lua
--   return {
--       id = "darter", sides = 3, radius = 11, speed = 130, hp = 2,
--       color = "hostile", -- a key in game/palette.lua, not a literal
--       behave = function(self, dt, ctx) ... end, -- optional, defaults to chase
--       drops = { { id = "scrap", min = 1, max = 3 }, { id = "core", chance = 0.1 } },
--   }
--
-- A spec that fails to load is skipped and logged rather than taking the game
-- down with it.

local Entity = require "game.entity"
local Palette = require "game.palette"
local Math = require "utils.math"

local Enemies = {
    specs = {}, -- id -> spec
    ids = {},   -- sorted, so random picks don't depend on directory order
    loaded = false,
}

local DIR = "game/enemies"
local MODULE = "game.enemies."

local CONTACT_GAP = 2      -- world units an enemy stops short of touching its target
local SEPARATION_PUSH = 1.2 -- how hard overlapping enemies shove each other apart
local HP_BAR_W = 26
local HP_BAR_H = 3
local HP_BAR_GAP = 8

local Enemy = Entity.extend()
Enemies.Enemy = Enemy

function Enemy.new(spec, x, y)
    local self = Entity.init(setmetatable({}, Enemy), {
        x = x, y = y,
        radius = spec.radius,
        sides = spec.sides,
        color = Palette[spec.color] or Palette.hostile,
        hp = spec.hp,
    })
    self.spec = spec
    self.speed = spec.speed
    return self
end

-- the default behaviour: walk at the player, stop just short of standing inside them
function Enemy:chase(dt, ctx)
    local distance, dx, dy = self:distanceTo(ctx.player)
    if distance < 0.001 then return end

    self.facing = math.atan2(dy, dx)
    if distance <= self.radius + ctx.player.radius + CONTACT_GAP then return end

    self.vx = self.vx + dx / distance * self.speed
    self.vy = self.vy + dy / distance * self.speed
end

-- keeps a pack from collapsing into a single stack on top of the player
function Enemy:separate(others)
    for _, other in ipairs(others) do
        if other ~= self then
            local distance, dx, dy = self:distanceTo(other)
            local reach = self.radius + other.radius
            if distance > 0.001 and distance < reach then
                local push = (1 - distance / reach) * self.speed * SEPARATION_PUSH
                self.vx = self.vx - dx / distance * push
                self.vy = self.vy - dy / distance * push
            end
        end
    end
end

function Enemy:update(dt, ctx)
    Entity.update(self, dt)

    self.vx, self.vy = 0, 0
    -- a staggered enemy still gets shoved by the knockback, it just can't steer
    if self.stagger <= 0 then
        local behave = self.spec.behave or Enemy.chase
        behave(self, dt, ctx)
    end
    self:separate(ctx.enemies)

    self:moveBy((self.vx + self.kx) * dt, (self.vy + self.ky) * dt)
end

function Enemy:draw()
    Entity.draw(self)
    if self.hp >= self.maxHp then return end

    local width, height = HP_BAR_W, HP_BAR_H
    local x = self.x - width / 2
    local y = self:drawY() - self.radius - HP_BAR_GAP
    love.graphics.setColor(Palette.healthTrack)
    love.graphics.rectangle("fill", x, y, width, height)
    love.graphics.setColor(Palette.health)
    love.graphics.rectangle("fill", x, y, width * math.max(0, self.hp) / self.maxHp, height)
    love.graphics.setColor(1, 1, 1, 1)
end

-- rolls a spec's loot table once, into { { id = ..., count = n }, ... }.
-- No `chance` means it always drops; no min/max means exactly one.
function Enemies.rollDrops(spec)
    local rolled = {}
    for _, drop in ipairs(spec.drops or {}) do
        if not drop.chance or math.random() < drop.chance then
            rolled[#rolled + 1] = {
                id = drop.id,
                count = Math.randInt(drop.min or 1, drop.max or 1),
            }
        end
    end
    return rolled
end

local function register(spec)
    Enemies.specs[spec.id] = spec
    Enemies.ids[#Enemies.ids + 1] = spec.id
end

local function loadSpec(name)
    local ok, spec = pcall(require, MODULE .. name)
    if not ok or type(spec) ~= "table" or type(spec.id) ~= "string" then
        print(("[enemies] skipping '%s': %s"):format(name, tostring(spec)))
        return
    end
    if Enemies.specs[spec.id] then
        print(("[enemies] skipping '%s': id '%s' is already registered"):format(name, spec.id))
        return
    end
    register(spec)
end

function Enemies.load()
    if Enemies.loaded then return end
    Enemies.loaded = true

    for _, file in ipairs(love.filesystem.getDirectoryItems(DIR)) do
        local name = file:match("^(.+)%.lua$")
        if name then loadSpec(name) end
    end
    table.sort(Enemies.ids)
end

function Enemies.spawn(id, x, y)
    local spec = Enemies.specs[id]
    if not spec then return nil end
    return Enemy.new(spec, x, y)
end

function Enemies.random(x, y)
    local count = #Enemies.ids
    if count == 0 then return nil end
    return Enemies.spawn(Enemies.ids[math.random(count)], x, y)
end

return Enemies
