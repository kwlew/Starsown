--- One run: the world, its camera and the player, fixed-stepped.

local Camera = require("game.camera")
local Commands = require("game.debug.commands")
local Entities = require("game.entities")
local FixedStep = require("game.fixedStep")
local Globals = require("globals")
local Ground = require("game.ground")
local Summary = require("game.debug.summary")
local Tile = require("game.tile")
local World = require("game.world")
local WorldOverlay = require("game.debug.worldOverlay")

local Engine = {}
Engine.__index = Engine

local TICK_RATE = Globals.world.tickRate
local WORLD_W, WORLD_H = Tile.px(Globals.world.widthTiles), Tile.px(Globals.world.heightTiles)
local RESPAWN_GRACE = 2 -- seconds a fresh player can't be hurt

---@return table
function Engine.new()
    local world = World.new(WORLD_W, WORLD_H)
    local camera = Camera.new(world)
    world.camera = camera -- the player aims through it
    local self = setmetatable({
        world = world,
        camera = camera,
        clock = FixedStep.new(TICK_RATE),
        showDebug = false,
        spawnX = WORLD_W / 2, spawnY = WORLD_H / 2,
    }, Engine)
    self:spawnPlayer()
    return self
end

---@return table
function Engine:spawnPlayer()
    self.player = self.world:spawn(Entities.Player, self.spawnX, self.spawnY)
    self.camera:cut(self.player.x, self.player.y)
    return self.player
end

---@return boolean # dead and not yet respawned
function Engine:playerDead()
    return not self.player:isValid()
end

--- a fresh player; the world carries on
function Engine:respawn()
    if not self:playerDead() then return end
    self:spawnPlayer().invulnerable = RESPAWN_GRACE
end

---@param dt number
function Engine:update(dt)
    self.clock:advance(dt, function(tick) self.world:tick(tick) end)
    local alpha = self.clock:alpha()
    if self.player:isValid() then -- before frame(), so aim uses this view
        local x, y = self.player:lerpPosition(alpha)
        self.camera:follow(x, y, dt)
    end
    self.world:frame(dt, alpha)
end

function Engine:resize()
    self.camera:reclamp()
end

---@param key string
function Engine:chordpressed(key)
    Commands.run(self, key)
end

function Engine:draw()
    local alpha = self.clock:alpha()
    self.camera:attach()
    Ground.draw(self.world, self.camera)
    self.world:draw(alpha)
    if self.showDebug then WorldOverlay.draw(self.world, alpha) end
    self.camera:detach()
    if self.showDebug then Summary.draw(self.world, self.camera) end
end

return Engine
