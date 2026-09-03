--- The game screen: a survival RPG in the making. What exists so far is the
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
local SPAWN_NEAR, SPAWN_FAR = 1.05, 1.35
local DESPAWN = 3

--- nearer the camera means standing lower, so ground y decides what overlaps
-- what; a body that leaves the ground must not slide behind what it was in
-- front of, which drawn y would do
---@param a table
---@param b table
---@return boolean
local function byGroundY(a, b) return a.y < b.y end

local INVENTORY_KEY = "e"
local PAUSE_CHORD = "p"
local INVENTORY_SLOTS = 24

--- the pause menu, built once and reused -- it outlives any single run, which
-- is what lets Options come back without wiping the world
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

--- a fresh world, player, bag and enemies. Only called on arriving from the
-- main menu (or with nothing built yet), so coming back from Options resumes
-- the run in progress.
function Play:startRun()
    self.world = Game.World.new{}
    self.player = Game.Player.new(0, 0)
    self.inventory = Game.Inventory.new{ slots = INVENTORY_SLOTS }
    self.bag = Game.InventoryPanel.new(self.inventory)
    self.enemyManager = Game.EnemyManager.new()
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

    self.ctx = {
        world = self.world,
        player = self.player,
        enemies = self.enemyManager.list,
        enemyManager = self.enemyManager,
        camera = self.camera,
        pointerX = self.player.aimX, pointerY = self.player.aimY,
    }

    if self.pause then self.pause:close() end
end

---@param previousName string|nil # only "mainMenu" starts a new run
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

    if not self.world or previousName == "mainMenu" then
        self:startRun()
    end

    self:layout()
end

--- call on resize; the world itself needs none
function Play:layout()
    self.pause:layout()
    self.bag:layout()
end

---@return boolean # derived, never stored, so the two kinds of pause can't disagree
function Play:isPaused()
    return self.pause:isOpen() or self.quietPause
end

--- closes the pause menu and drops whatever keys were held behind it
function Play:resume()
    self.pause:close()
    self.player:releaseAll()
end

--- freezes the world and hands all input to the menu
function Play:openPause()
    UI.Sfx.press()
    self.player:releaseAll() -- or the key held to reach the menu stays down behind it
    self.pause:openMenu()
end

--- the world keeps running while the bag is open; it only takes the player's
-- hands off it
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

--- one enemy at a time, on a timer, just outside the view and under the cap
---@param dt number
---@param offscreen number # distance from the player to the corner of the view
function Play:spawnStep(dt, offscreen)
    if self.enemyManager:count() >= ENEMY_CAP then return end

    self.spawnTimer = self.spawnTimer + dt
    if self.spawnTimer < SPAWN_INTERVAL then return end
    self.spawnTimer = 0

    local x, y = Math.polar(self.player.x, self.player.y, Math.randAngle(),
        Math.randRange(offscreen * SPAWN_NEAR, offscreen * SPAWN_FAR))

    self.enemyManager:spawnRandom(x, y)
end

--- everything a kill leaves behind goes straight to the bag; there are no ground
-- items yet, so this is where loot enters the game
---@param enemy Enemy
function Play:collect(enemy)
    for _, drop in ipairs(Game.Enemies.rollDrops(enemy.spec)) do
        self.inventory:add(drop.id, drop.count)
    end
end

--- Darkwood keeps the hardware pointer itself inside the ring, not just the
-- cursor drawn over it. Without this the OS pointer wanders off past the ring
-- while the aim stays pinned, so pushing out and coming back leaves a dead
-- zone the width of however far it strayed -- and with the custom cursor
-- turned off there was nothing visibly holding it at all.
--
-- Only while the pointer is ours to move: an overlay wants it free, and
-- warping an unfocused window's pointer would yank it out of whatever the
-- player alt-tabbed to.
function Play:tetherPointer()
    if self.bag:isOpen() or self.pause:isOpen() then return end
    if not self.player.aimPinned then return end
    if not love.window.hasFocus() then return end

    love.mouse.setPosition(self.camera:toScreen(self.player.aimX, self.player.aimY))
end

--- true while the cursor sits on something worth pointing at; the cursor picks
-- up its hover color from this
---@return boolean
function Play:aimOverEnemy()
    local player = self.player
    for _, enemy in ipairs(self.enemyManager.list) do
        if Math.length(enemy.x - player.aimX, enemy:drawY() - player.aimY) <= enemy.radius then
            return true
        end
    end
    return false
end

--- the whole run: aim, player, enemies, the loot and particles a kill leaves,
-- spawning, and the camera. Both kinds of pause return before any of it.
---@param dt number
function Play:update(dt)
    if self.pause:isOpen() then
        self.pause:update(dt)
        return
    end
    if self.quietPause then return end

    local ctx, player = self.ctx, self.player
    if self.bag:isOpen() then
        ctx.pointerX, ctx.pointerY = player.aimX, player.aimY
    else
        ctx.pointerX, ctx.pointerY = self.camera:toWorld(love.mouse.getPosition())
    end

    player:update(dt, ctx)
    self:tetherPointer() -- after the aim is final, so a walking player drags it along

    local offscreen = Math.length(self.camera:halfExtents())
    local despawnAt = offscreen * DESPAWN

    self.enemyManager:update(dt, ctx)
    for _, enemy in ipairs(self.enemyManager:prune(player, despawnAt)) do
        self.deaths:spawn(enemy.x, enemy:drawY(), enemy.color)
        self:collect(enemy)
    end

    self.deaths:update(dt)
    self:spawnStep(dt, offscreen)

    self.camera:follow(player.x, player.y, dt)
end

---@param w number
---@param h number
---@param rescaled boolean # the UI scale changed, so the camera zoom follows it
function Play:resize(w, h, rescaled)
    if rescaled then self.camera.zoom = UI.Theme.scale end
    self:layout()
end

--- F3 + P is the quiet pause: the world freezes with nothing drawn over it
---@param key string # the key held with F3
function Play:chordpressed(key)
    if key == PAUSE_CHORD then
        self.quietPause = not self.quietPause
        self.player:releaseAll()
    end
end

--- routed by what's open: the pause menu takes everything, the inventory takes
-- only its own close keys, and otherwise it reaches the player
---@param key string
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

---@param key string
function Play:keyreleased(key)
    self.player:keyreleased(key)
end

---@param x number
---@param y number
function Play:mousemoved(x, y)
    if self.pause:isOpen() then self.pause:mousemoved(x, y) end
    if self.bag:isOpen() then self.bag:mousemoved(x, y) end
end

---@param x number
---@param y number
---@param button integer
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

---@param x number
---@param y number
---@param button integer
function Play:mousereleased(x, y, button)
    if self.pause:isOpen() then
        self.pause:mousereleased(x, y, button)
        return
    end
    if button == 1 then self.player:setAttacking(false) end
end

--- the pause menu and the inventory both need the pointer, so the tether only
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

--- shadows all go down before any body, or a nearer entity's shadow lands on
-- top of a farther entity that was already painted
function Play:drawEntities()
    local list = self.drawList
    for i = #list, 1, -1 do list[i] = nil end

    list[1] = self.player
    for _, enemy in ipairs(self.enemyManager.list) do list[#list + 1] = enemy end
    table.sort(list, byGroundY)

    for _, entity in ipairs(list) do entity:drawGround() end
    for _, entity in ipairs(list) do entity:draw() end
end

--- the world through the camera, then the screen-space chrome: hint line,
-- inventory, pause menu, debug panel, cursor
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

    if not self.bag:isOpen() and not self.pause:isOpen() then
        UI.Label.hint(I18n.t("game.hint"), true)
    end
    if self.bag:isOpen() then self.bag:draw() end
    if self.pause:isOpen() then self.pause:draw() end

    if Game.DebugOverlay.visible then
        self.ctx.pauseState = self.pause:isOpen() and "pause menu"
            or self.quietPause and "paused (F3+P)" or "running"
        Game.DebugOverlay.drawScreen(self.ctx)
    end

    self:drawCursor()
end

return Play
