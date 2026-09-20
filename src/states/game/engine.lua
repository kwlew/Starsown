-- src/states/game/engine.lua
-- This will be the main layer.
-- We will pass this as engine.run() to InGame.lua and that will make it so the game run.
-- TODO: Make a pause menu.
local World = require "states.game.rendering.world"
local Player = require "states.game.player"
local Chunks = require "states.game.chunks"
local Effects = require "states.game.effects"
local Spawn = require "states.game.spawn"
local Items = require "states.game.items"
local Math = require "utils.math"
local Globals = require "globals"
local Units = require "states.game.units"
local Inventory = require "states.game.inventory"
local Hotbar = require "states.game.rendering.hotbar"
local InventoryPanel = require "states.game.rendering.inventoryPanel"
local Hud = require "states.game.rendering.hud"
local DebugGUI = require "states.game.rendering.debugGUI"

local Engine = {}
Engine.__index = Engine

local CAMERA_FOLLOW = 8
local HOTBAR_SIZE = 8
local INVENTORY_SIZE = HOTBAR_SIZE * 4 -- the hotbar is the bottom row of four
local STARTER_ITEMS = { wood = 20, stone = 70, herb = 5, gem = 3, axe = 1, stone_sword = 1 } -- placeholders to try the UI with
local ZOOM_MIN, ZOOM_MAX, ZOOM_STEP, ZOOM_RATE = 0.25, 1, 1.25, 10 -- dev only; below ~0.25 drawing every tile gets slow
local SPEED_MIN, SPEED_MAX = 1, 32 -- dev only, doubles/halves per press
local CHUNK_RADIUS_MIN, CHUNK_RADIUS_MAX = 2, 5 -- chunks of trees kept around the camera; zoomed far out, the view outgrows the max
local CHUNKS_PER_FRAME = 2
local UPDATE_RANGE = 12 -- meters around the player whose trees are updated and collided

function Engine:load()
    Engine.WORLD = World.new()
    Engine.CHUNKS = Chunks.new(Engine.WORLD)
    Engine.EFFECTS = Effects.new()
    Engine.nearTrees, Engine.visibleTrees = {}, {}
    Engine.aimedTree, Engine.chopping = nil, false

    local col, row = Spawn.find(Engine.WORLD.seed, function(c, r) return Engine:isTileBlocked(c, r) end)
    Engine.spawn = { col = col, row = row }
    local spawnX, spawnY = World.tileCenter(col, row)
    Engine.PLAYER = Player.new(spawnX, spawnY)
    Engine.entities = { Engine.PLAYER }
    Engine.INVENTORY = Inventory.new(INVENTORY_SIZE, HOTBAR_SIZE)
    InventoryPanel.reset()
    for id, count in pairs(STARTER_ITEMS) do Engine.INVENTORY:add(id, count) end
    Engine.camX, Engine.camY = spawnX, spawnY
    Engine.zoom, Engine.zoomTarget, Engine.speedScale = 1, 1, 1
    Engine:streamChunks(math.huge)
end

--- Keeps trees loaded around the camera, out to what the view shows (up to a cap).
---@param budget number # new chunks allowed this call
function Engine:streamChunks(budget)
    local left, top, right, bottom = Engine:viewRect()
    local reach = math.max(right - left, bottom - top) / 2 / Chunks.SIZE
    local radius = math.max(CHUNK_RADIUS_MIN, math.min(CHUNK_RADIUS_MAX, math.ceil(reach) + 1))
    Engine.CHUNKS:stream(Engine.camX, Engine.camY, radius, budget)
end

--- Whether something solid stands on a tile, so the player can't spawn there.
---@param col integer
---@param row integer
---@return boolean
function Engine:isTileBlocked(col, row)
    return Engine.CHUNKS:isTreeAt(col, row)
end

--- The world-space rectangle the screen currently shows.
---@return number left
---@return number top
---@return number right
---@return number bottom
function Engine:viewRect()
    local w, h = love.graphics.getDimensions()
    local scale = Engine.zoom * Units.PPM
    local halfW, halfH = w / 2 / scale, h / 2 / scale
    return Engine.camX - halfW, Engine.camY - halfH, Engine.camX + halfW, Engine.camY + halfH
end

--- Screen -> world, undoing the camera translate in draw().
function Engine:toWorld(sx, sy)
    local scale = Engine.zoom * Units.PPM
    return Engine.camX + (sx - love.graphics.getWidth() / 2) / scale,
           Engine.camY + (sy - love.graphics.getHeight() / 2) / scale
end

function Engine:draw()
    local left, top, right, bottom = Engine:viewRect()

    love.graphics.push()
    love.graphics.scale(Engine.zoom * Units.PPM)
    love.graphics.translate(-left, -top)
    love.graphics.setLineWidth(Units.LINE)
    Engine.WORLD:draw(left, top, right, bottom)
    -- a margin past the screen so canopies and shadows don't pop at the edge
    local trees = Engine.CHUNKS:collect(Engine.visibleTrees, left - 3, top - 3, right + 3, bottom + 3)
    for _, tree in ipairs(trees) do
        tree:drawGround()
    end
    if Engine.aimedTree then Engine.aimedTree:drawHighlight(Engine.chopping and 1 or 0) end
    for _, tree in ipairs(trees) do
        tree:draw()
    end
    Engine.PLAYER:drawGround()
    Engine.PLAYER:draw()
    Engine.PLAYER:drawHealth()
    -- canopies (and any break progress) last, so they sit over the player
    for _, tree in ipairs(trees) do
        tree:drawCanopy(Engine.PLAYER.x, Engine.PLAYER.y)
        if tree.hp < tree.maxHp then tree:drawHealth() end
    end
    Engine.EFFECTS:draw()
    DebugGUI.drawWorld(Engine)
    love.graphics.pop()
    love.graphics.setLineWidth(1)

    Hud.draw(Engine.PLAYER)
    Hotbar.draw(Engine.INVENTORY)
    InventoryPanel.draw(Engine.INVENTORY)
    DebugGUI.draw(Engine)
end

function Engine:update(dt)
    local player = Engine.PLAYER
    local pointerX, pointerY = self:toWorld(love.mouse.getPosition())
    Engine.WORLD:update(dt)
    player:update(dt, { pointerX = pointerX, pointerY = pointerY, speedScale = Engine.speedScale })
    Engine.zoom = Math.damp(Engine.zoom, Engine.zoomTarget, ZOOM_RATE, dt)
    for _, entity in ipairs(Engine.entities) do
        if entity ~= player then entity:update(dt) end
    end
    local near = Engine.CHUNKS:collect(Engine.nearTrees, player.x - UPDATE_RANGE, player.y - UPDATE_RANGE,
        player.x + UPDATE_RANGE, player.y + UPDATE_RANGE)
    for _, tree in ipairs(near) do
        tree:update(dt)
        tree:collide(player)
    end
    Engine:chopAimedTree(dt)
    Engine.EFFECTS:update(dt)
    InventoryPanel.update(Engine.INVENTORY)

    Engine.camX = Math.damp(Engine.camX, player.x, CAMERA_FOLLOW, dt)
    Engine.camY = Math.damp(Engine.camY, player.y, CAMERA_FOLLOW, dt)
    Engine:streamChunks(CHUNKS_PER_FRAME)
end

--- The tree a swing would land on: the one whose trunk the aim point sits in,
-- nearest first when two overlap. The aim point is already clamped to
-- Player.RANGE, so reach needs no second check.
---@return table? tree
function Engine:findAimedTree()
    local player = Engine.PLAYER
    local best, bestDistance
    for _, tree in ipairs(Engine.nearTrees) do
        local radius = tree:hitRadius()
        local dx, dy = player.aimX - tree.x, player.aimY - tree.y
        local distance = dx * dx + dy * dy
        if distance <= radius * radius and (not bestDistance or distance < bestDistance) then
            best, bestDistance = tree, distance
        end
    end
    return best
end

--- Hold the left button to chop the aimed tree.
---@param dt number
function Engine:chopAimedTree(dt)
    if Engine:isInventoryOpen() then
        Engine.aimedTree, Engine.chopping = nil, false
        return
    end

    local tree = Engine:findAimedTree()
    Engine.aimedTree, Engine.chopping = tree, false
    if not tree or not love.mouse.isDown(1) then return end
    Engine.chopping = true

    local held = Engine.INVENTORY:selectedStack()
    local drops, removed = tree:breakWith(dt, {
        speed = Items.toolSpeed(held and held.id, tree:stageSpec().tool),
        effects = Engine.EFFECTS,
        fromX = Engine.PLAYER.x, fromY = Engine.PLAYER.y,
    })
    if drops then
        Engine.INVENTORY:add(drops.id, drops.count)
        Engine.CHUNKS:changed(tree, removed)
        if removed then Engine.aimedTree = nil end
    end
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

--- Zoom and speed keys; a no-op unless Globals.dev.enabled.
---@return boolean handled
function Engine:devKeypressed(key)
    if not Globals.dev.enabled then return false end

    if key == "-" or key == "kp-" then
        Engine.zoomTarget = Math.clamp(Engine.zoomTarget / ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
    elseif key == "=" or key == "kp+" then
        Engine.zoomTarget = Math.clamp(Engine.zoomTarget * ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
    elseif key == "0" then
        Engine.zoomTarget = 1
    elseif key == "[" then
        Engine.speedScale = Math.clamp(Engine.speedScale / 2, SPEED_MIN, SPEED_MAX)
    elseif key == "]" then
        Engine.speedScale = Math.clamp(Engine.speedScale * 2, SPEED_MIN, SPEED_MAX)
    else
        return false
    end
    return true
end

function Engine:keypressed(key)
    if Engine:devKeypressed(key) then return end
    if key == "f4" then DebugGUI.toggle() return end
    if key == "f5" then DebugGUI.toggleBiomes() return end
    if key == "e" then InventoryPanel.toggle(Engine.INVENTORY) return end
    if key == "c" then InventoryPanel.toggleCrafting(Engine.INVENTORY) return end

    local slot = tonumber(key)
    if slot and slot >= 1 and slot <= HOTBAR_SIZE then
        -- while the panel's open, number keys only move slots - never fall
        -- through to changing the active hotbar slot behind it
        if InventoryPanel.open then
            InventoryPanel.moveToSlot(Engine.INVENTORY, slot)
        else
            Engine.INVENTORY:select(slot)
        end
        return
    end
    Engine.PLAYER:keypressed(key)
end

function Engine:keyreleased(key)
    Engine.PLAYER:keyreleased(key)
end

return Engine
