-- src/states/game/engine.lua
-- This will be the main layer.
-- We will pass this as engine.run() to InGame.lua and that will make it so the game run.
-- TODO: Make a pause menu.
local World = require "states.game.rendering.world"
local Player = require "states.game.player"
local Math = require "utils.math"
local Inventory = require "states.game.inventory"
local Hotbar = require "states.game.rendering.hotbar"
local InventoryPanel = require "states.game.rendering.inventoryPanel"
local Hud = require "states.game.rendering.hud"
local DebugGUI = require "states.game.rendering.debugGUI"

local Engine = {}
Engine.__index = Engine

local CAMERA_FOLLOW = 8
local HOTBAR_SIZE = 6
local INVENTORY_SIZE = HOTBAR_SIZE * 4 -- the hotbar is the bottom row of four
local STARTER_ITEMS = { wood = 20, stone = 70, herb = 5, gem = 3 } -- placeholders to try the UI with

function Engine:load()
    Engine.WORLD = World.new()
    Engine.PLAYER = Player.new(0, 0)
    Engine.entities = { Engine.PLAYER }
    Engine.INVENTORY = Inventory.new(INVENTORY_SIZE, HOTBAR_SIZE)
    InventoryPanel.open = false
    for id, count in pairs(STARTER_ITEMS) do Engine.INVENTORY:add(id, count) end
    Engine.camX, Engine.camY = 0, 0
end

--- Screen -> world, undoing the camera translate in draw().
function Engine:toWorld(sx, sy)
    return sx + Engine.camX - love.graphics.getWidth() / 2,
           sy + Engine.camY - love.graphics.getHeight() / 2
end

function Engine:draw()
    local w, h = love.graphics.getDimensions()
    local left, top = Engine.camX - w / 2, Engine.camY - h / 2

    love.graphics.push()
    love.graphics.translate(-left, -top)
    Engine.WORLD:draw(left, top, left + w, top + h)
    Engine.PLAYER:drawGround()
    Engine.PLAYER:draw()
    Engine.PLAYER:drawHealth()
    DebugGUI.drawWorld(Engine)
    love.graphics.pop()

    Hud.draw(Engine.PLAYER)
    Hotbar.draw(Engine.INVENTORY)
    InventoryPanel.draw(Engine.INVENTORY)
    DebugGUI.draw(Engine)
end

function Engine:update(dt)
    local player = Engine.PLAYER
    local pointerX, pointerY = self:toWorld(love.mouse.getPosition())
    Engine.WORLD:update(dt)
    player:update(dt, { pointerX = pointerX, pointerY = pointerY })
    for _, entity in ipairs(Engine.entities) do
        if entity ~= player then entity:update(dt) end
    end

    Engine.camX = Math.damp(Engine.camX, player.x, CAMERA_FOLLOW, dt)
    Engine.camY = Math.damp(Engine.camY, player.y, CAMERA_FOLLOW, dt)
end

function Engine:isInventoryOpen()
    return InventoryPanel.open
end

function Engine:closeInventory()
    InventoryPanel.close(Engine.INVENTORY)
end

function Engine:mousepressed(x, y, button)
    if InventoryPanel.mousepressed(Engine.INVENTORY, x, y, button) then return true end
    return DebugGUI.mousepressed(Engine, x, y, button)
end

function Engine:wheelmoved(_, dy)
    if dy ~= 0 then Engine.INVENTORY:select(Engine.INVENTORY.selected - (dy > 0 and 1 or -1)) end
end

function Engine:keypressed(key)
    if key == "f4" then DebugGUI.toggle() return end
    if key == "e" then InventoryPanel.toggle(Engine.INVENTORY) return end

    local slot = tonumber(key)
    if slot and slot >= 1 and slot <= HOTBAR_SIZE then Engine.INVENTORY:select(slot) return end
    Engine.PLAYER:keypressed(key)
end

function Engine:keyreleased(key)
    Engine.PLAYER:keyreleased(key)
end

return Engine
