--- One run's simulation: owns the world and steps it at a fixed tick rate.
-- The in-game screen only creates it, drives it while unpaused and draws it.

local UI = require "ui"
local Player = require "game.player"

local Engine = {}
Engine.__index = Engine

local TICK_RATE = 20
local TICK = 1 / TICK_RATE
local MAX_TICKS_PER_FRAME = 5 -- after a long hitch, drop the backlog instead of fast-forwarding through it

---@return table
function Engine.new()
    local s = UI.Theme.scale
    return setmetatable({
        accumulator = 0,
        player = Player.new(love.graphics.getWidth() / 2 / s, love.graphics.getHeight() / 2 / s),
    }, Engine)
end

--- runs as many fixed ticks as the elapsed time covers
---@param dt number
function Engine:update(dt)
    self.accumulator = self.accumulator + dt
    local ticks = 0
    while self.accumulator >= TICK and ticks < MAX_TICKS_PER_FRAME do
        self:tick(TICK)
        self.accumulator = self.accumulator - TICK
        ticks = ticks + 1
    end
    if ticks == MAX_TICKS_PER_FRAME then self.accumulator = math.min(self.accumulator, TICK) end
end

---@param dt number # always TICK
function Engine:tick(dt)
    self.player:tick(dt)
end

function Engine:resize()
    self.player:clamp()
    self.player:snap()
end

function Engine:draw()
    self.player:draw(self.accumulator / TICK)
end

return Engine
