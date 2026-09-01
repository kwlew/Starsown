-- The game screen: a survival RPG in the making. What exists so far is the
-- ground, one enemy type, a melee swing, an inventory the drops go into, and
-- the pause states around them.
--
-- Three things can be "open" over the world and they are not the same thing:
--   * the pause menu freezes the world and takes all input
--   * a quiet pause (F3 + P) freezes it with nothing drawn over it
--   * the inventory leaves the world running but takes the player's hands off it
-- isPaused() is derived from the first two rather than stored, so the two can
-- never disagree about whether time is passing.

local StateManager = require "core.stateManager"
local Audio = require "core.audio"
local Presence = require "services.presence"
local Particles = require "particles"
local UI = require "ui"
local I18n = require "core.i18n"
local Globals = require "globals"
local Math = require "utils.math"
local Game = require "game"

local Play = {}

local ENEMY_CAP = 6
local SPAWN_INTERVAL = 2.5
-- as multiples of the view's half-diagonal, so enemies always walk in from just
-- off-screen whatever the resolution or zoom
local SPAWN_NEAR, SPAWN_FAR = 1.05, 1.35
-- an open world means you can simply walk away; without this the cap fills up
-- with stragglers trailing off in the dark and nothing new spawns near you
local DESPAWN = 3

-- nearer the camera means standing lower, so ground y decides what overlaps
-- what; a body that leaves the ground must not slide behind what it was in
-- front of, which drawn y would do
local function byGroundY(a, b) return a.y < b.y end

local INVENTORY_KEY = "e"
local PAUSE_CHORD = "p"
local INVENTORY_SLOTS = 24

function Play:buildOverlays()
    if self.pause then return end

    self.pause = Game.PauseMenu.new{
        onCancel = function() self:resume() end,
        items = {
            { label = function() return I18n.t("game.pause.resume") end,
              onSelect = function() UI.Sfx.select() self:resume() end },
            { label = function() return I18n.t("game.pause.options") end,
              onSelect = function()
                  UI.Sfx.select()
                  StateManager.fadeTo("options", { returnTo = "play" })
              end },
            { label = function() return I18n.t("game.pause.quit") end, danger = true,
              onSelect = function() UI.Sfx.select() StateManager.fadeTo("mainMenu") end },
        },
    }
end

function Play:startRun()
    self.world = Game.World.new{}
    self.player = Game.Player.new(0, 0)
    self.inventory = Game.Inventory.new{ slots = INVENTORY_SLOTS }
    self.bag = Game.InventoryPanel.new(self.inventory)
    self.enemies = {}
    self.drawList = {} -- reused every frame; entities sorted for overlap order
    self.spawnTimer = 0
    self.quietPause = false

    self.deaths = Particles.Burst.new{
        countMin = 14, countMax = 20,
        sizeMin = 1.2, sizeMax = 3.2,
        speedMin = 60, speedMax = 220,
        lifeMin = 0.30, lifeMax = 0.70,
        drag = 4,
    }

    self.camera = Game.Camera.new{ zoom = UI.Theme.scale }
    self.camera:snapTo(self.player.x, self.player.y)

    -- one table reused every frame; the player, the enemies and the debug
    -- overlay all read the same view of the world from it
    self.ctx = {
        world = self.world,
        player = self.player,
        enemies = self.enemies,
        camera = self.camera,
        pointerX = self.player.aimX, pointerY = self.player.aimY,
    }

    if self.pause then self.pause:close() end
end

function Play:enter(previousName)
    Audio.stop("music") -- Music.stop only forgets what was playing
    UI.Music.stop()
    Presence.set{
        details = "Playing",
        state = "Exploring the grid",
        smallText = "In game",
        startedAt = Globals.game.startedAt,
    }

    Game.Enemies.load()
    Game.Items.load()
    self:buildOverlays()

    -- Options is reachable from the pause menu, so coming back must not wipe
    -- the run; only arriving from the menu starts a new one.
    if not self.world or previousName == "mainMenu" then
        self:startRun()
    end

    self:layout()
end

function Play:layout()
    self.pause:layout()
    self.bag:layout()
end

function Play:isPaused()
    return self.pause:isOpen() or self.quietPause
end

function Play:resume()
    self.pause:close()
    self.player:releaseAll()
end

function Play:openPause()
    UI.Sfx.press()
    self.player:releaseAll() -- or the key held to reach the menu stays down behind it
    self.pause:openMenu()
end

function Play:toggleInventory()
    if self.bag:isOpen() then
        self.bag:close()
    else
        self.player:releaseAll()
        self.bag:openPanel()
        self.bag:mousemoved(love.mouse.getPosition())
    end
    UI.Sfx.press()
end

function Play:spawnStep(dt, offscreen)
    if #self.enemies >= ENEMY_CAP then return end

    self.spawnTimer = self.spawnTimer + dt
    if self.spawnTimer < SPAWN_INTERVAL then return end
    self.spawnTimer = 0

    local x, y = Math.polar(self.player.x, self.player.y, Math.randAngle(),
        Math.randRange(offscreen * SPAWN_NEAR, offscreen * SPAWN_FAR))

    local enemy = Game.Enemies.random(x, y)
    if enemy then self.enemies[#self.enemies + 1] = enemy end
end

-- everything a kill leaves behind goes straight to the bag; there are no ground
-- items yet, so this is where loot enters the game
function Play:collect(enemy)
    for _, drop in ipairs(Game.Enemies.rollDrops(enemy.spec)) do
        self.inventory:add(drop.id, drop.count)
    end
end

-- true while the cursor sits on something worth pointing at; the cursor picks
-- up its hover color from this
function Play:aimOverEnemy()
    local player = self.player
    for _, enemy in ipairs(self.enemies) do
        -- against the drawn body, not the feet: this only colors the cursor,
        -- and it should light up when the cursor looks like it is on something
        if Math.length(enemy.x - player.aimX, enemy:drawY() - player.aimY) <= enemy.radius then
            return true
        end
    end
    return false
end

function Play:update(dt)
    if self.pause:isOpen() then
        self.pause:update(dt)
        return
    end
    if self.quietPause then return end

    local ctx, player = self.ctx, self.player
    if self.bag:isOpen() then
        -- hands are on the inventory, so the aim holds where it was left
        ctx.pointerX, ctx.pointerY = player.aimX, player.aimY
    else
        -- polled rather than tracked through mousemoved, so aim is right even
        -- when the pointer re-enters the window without moving
        ctx.pointerX, ctx.pointerY = self.camera:toWorld(love.mouse.getPosition())
    end

    player:update(dt, ctx)

    local offscreen = Math.length(self.camera:halfExtents())
    local despawnAt = offscreen * DESPAWN

    for i = #self.enemies, 1, -1 do
        local enemy = self.enemies[i]
        enemy:update(dt, ctx)
        if enemy.dead then
            self.deaths:spawn(enemy.x, enemy:drawY(), enemy.color)
            self:collect(enemy)
            table.remove(self.enemies, i)
        elseif player:distanceTo(enemy) > despawnAt then
            table.remove(self.enemies, i) -- left far behind, and far out of sight
        end
    end

    self.deaths:update(dt)
    self:spawnStep(dt, offscreen)

    self.camera:follow(player.x, player.y, dt)
end

function Play:resize(w, h, rescaled)
    if rescaled then self.camera.zoom = UI.Theme.scale end
    self:layout()
end

function Play:chordpressed(key)
    -- F3 + P: freeze with nothing drawn over it, so the world can be looked at
    if key == PAUSE_CHORD then
        self.quietPause = not self.quietPause
        self.player:releaseAll()
    end
end

function Play:keypressed(key)
    if key == "f4" then
        Game.DebugOverlay.toggle()
        return
    end

    if self.pause:isOpen() then
        self.pause:keypressed(key)
        return
    end

    if self.bag:isOpen() then
        if key == "escape" or key == INVENTORY_KEY then self:toggleInventory() end
        return
    end

    if key == "escape" then
        self:openPause()
        return
    end
    if key == INVENTORY_KEY then
        self:toggleInventory()
        return
    end

    self.player:keypressed(key)
end

function Play:keyreleased(key)
    self.player:keyreleased(key)
end

function Play:mousemoved(x, y)
    if self.pause:isOpen() then self.pause:mousemoved(x, y) end
    if self.bag:isOpen() then self.bag:mousemoved(x, y) end
end

function Play:mousepressed(x, y, button)
    if self.pause:isOpen() then
        self.pause:mousepressed(x, y, button)
        return
    end
    if self.bag:isOpen() then
        self.bag:mousepressed(x, y, button)
        return
    end
    if button == 1 then self.player:setAttacking(true) end
end

function Play:mousereleased(x, y, button)
    if self.pause:isOpen() then
        self.pause:mousereleased(x, y, button)
        return
    end
    if button == 1 then self.player:setAttacking(false) end
end

-- the pause menu and the inventory both need the pointer, so the tether only
-- claims the cursor while the player's hands are actually on the world
function Play:drawCursor()
    if self.pause:isOpen() then
        UI.Cursor.setHover(self.pause:hovering(love.mouse.getPosition()))
        return
    end
    if self.bag:isOpen() then
        UI.Cursor.setHover(self.bag.hovered ~= nil)
        return
    end

    UI.Cursor.setPosition(self.camera:toScreen(self.player.aimX, self.player.aimY))
    UI.Cursor.setHover(self:aimOverEnemy())
end

-- shadows all go down before any body, or a nearer entity's shadow lands on
-- top of a farther entity that was already painted
function Play:drawEntities()
    local list = self.drawList
    for i = #list, 1, -1 do list[i] = nil end

    list[1] = self.player
    for _, enemy in ipairs(self.enemies) do list[#list + 1] = enemy end
    table.sort(list, byGroundY)

    for _, entity in ipairs(list) do entity:drawGround() end
    for _, entity in ipairs(list) do entity:draw() end
end

function Play:draw()
    self.camera:attach()
    self.world:draw(self.camera:view())

    self:drawEntities()
    self.player.swipe:draw()
    self.deaths:draw()

    if Game.DebugOverlay.visible then
        Game.DebugOverlay.drawWorld(self.ctx)
    end
    self.camera:detach()

    -- the hint describes controls that do nothing behind an overlay
    if not self.bag:isOpen() and not self.pause:isOpen() then
        UI.Label.hint(I18n.t("game.hint"), true)
    end
    if self.bag:isOpen() then self.bag:draw() end
    if self.pause:isOpen() then self.pause:draw() end

    if Game.DebugOverlay.visible then
        -- a quiet pause draws nothing of its own, so the overlay is the only
        -- place it is visible at all
        self.ctx.pauseState = self.pause:isOpen() and "pause menu"
            or self.quietPause and "paused (F3+P)" or "running"
        Game.DebugOverlay.drawScreen(self.ctx)
    end

    self:drawCursor()
end

return Play
