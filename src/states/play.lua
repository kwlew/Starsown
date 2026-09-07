--- The game screen: a survival RPG in the making. What exists so far is the
-- ground, one enemy type, a melee swing, an inventory the drops go into, and
-- the pause states around them.
--
-- Five things can be "open" over the world and they are not the same thing:
--   * the pause menu freezes the world and takes all input
--   * a quiet pause (F3 + P) freezes it with nothing drawn over it
--   * the inventory leaves the world running but takes the player's hands off it
--   * the shop panel leaves the player's movement alone, since walking away
--     from the NPC it's open for is what closes it (see Play:update)
--   * the dialogue/quest box freezes the world like the pause menu does --
--     it's a deliberate modal prompt, not a live panel to browse mid-stride
-- isPaused() is derived from the first two rather than stored, so the two can
-- never disagree about whether time is passing.

local StateManager = require "core.stateManager"
local Audio = require "core.audio"
local Assets = require "core.assets"
local Save = require "core.save"
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
local DEFAULT_KILL_XP = 5       -- combat xp for a kill whose spec doesn't set its own xpReward
local DEFAULT_KILL_CURRENCY = 2 -- likewise for currency, when a spec sets no currencyReward

--- nearer the camera means standing lower, so ground y decides what overlaps
-- what; a body that leaves the ground must not slide behind what it was in
-- front of, which drawn y would do
---@param a table
---@param b table
---@return boolean
local function byGroundY(a, b) return a.y < b.y end

local INVENTORY_KEY = "e"
local INTERACT_KEY = "f"
local PAUSE_CHORD = "p"
local INVENTORY_SLOTS = 24
local INTERACT_GAP = 46 -- world units past body-to-body contact that still counts as "close enough to talk"

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
              onSelect = function()
                  UI.Sfx.select()
                  self:persist()
                  StateManager.fadeTo("mainMenu")
              end },
        },
    }

    -- rebuilt per-prompt (see Play:openDialogue/openQuest) since its title,
    -- message and buttons all vary by what's being opened -- this is just
    -- the placeholder so isOpen()/layout()/etc. always have something to
    -- call before the first real one exists
    self.dialog = UI.Dialog.new{}
    self.dialog:setFocusSound(UI.Sfx.focus)
end

--- everything that only ever happens once per run: a fresh player, inventory
-- and bag, the world (there's exactly one, now -- see game/world.lua), the
-- NPC roster, the shared particle pools, and the draw-order scratch buffer.
-- Only called on arriving from the main menu (or with nothing built yet);
-- coming back from Options must not call this, or the run in progress
-- would be lost.
function Play:newGame()
    self.player = Game.Player.new(0, 0)
    Game.Hud.reset() -- a new run's hp starts full; the bar shouldn't animate up to it
    self.inventory = Game.Inventory.new{ slots = INVENTORY_SLOTS }
    self.bag = Game.InventoryPanel.new(self.inventory, self.player.equipped)
    self.shop = Game.ShopPanel.new(self.inventory, {
        get = function() return self.currency end,
        spend = function(amount) self.currency = self.currency - amount end,
        earn = function(amount) self.currency = self.currency + amount end,
    })
    self.drawList = {} -- reused every frame; entities sorted for overlap order
    self.quietPause = false
    self.nearbyNpc = nil     -- the Npc in interact range, if any; drives the prompt and the F key
    self.interactingNpc = nil -- id of whichever NPC self.shop is currently open for

    self.currency = 0
    self.skills = {} -- id -> { xp = number }; see game/skills.lua
    self.quests = {} -- id -> { progress = number, complete = boolean }; see game/quests.lua
    self.stats = { kills = 0, itemsGathered = 0, playtime = 0 }
    self:loadProgress()

    self.deaths = Particles.Burst.new{
        countMin = 14, countMax = 20,
        sizeMin = 1.2, sizeMax = 3.2,
        speedMin = 60, speedMax = 220,
        lifeMin = 0.30, lifeMax = 0.70,
        drag = 4,
    }

    if self.pause then self.pause:close() end

    self.world = Game.World.new()
    self.camera = Game.Camera.new{ zoom = UI.Theme.scale }
    self.camera:snapTo(self.player.x, self.player.y)

    self.ctx = {
        world = self.world,
        player = self.player,
        camera = self.camera,
        pointerX = self.player.aimX, pointerY = self.player.aimY,
    }

    self:resetNpcs()
    self:resetEnemies()
end

--- the one NpcManager for the whole world, populated once from every
-- registered area's own `npcs` list combined (see game/areas.lua) -- an
-- NPC is permanent world furniture, there's no transition to rebuild it on
-- any more.
function Play:resetNpcs()
    self.npcManager = Game.NpcManager.new()
    for _, id in ipairs(Game.Areas.ids) do
        for _, entry in ipairs(Game.Areas.get(id).npcs or {}) do
            self.npcManager:spawn(entry.id, entry.x, entry.y)
        end
    end
end

--- a fresh, empty EnemyManager and the ctx/spawnTimer fields that go with it
-- -- shared by newGame (the first roster) and onPlayerDeath (dying clears
-- the enemies around you without rebuilding the world itself)
function Play:resetEnemies()
    self.enemyManager = Game.EnemyManager.new()
    self.spawnTimer = 0
    self.ctx.enemies = self.enemyManager.list
    self.ctx.enemyManager = self.enemyManager
end

--- pulls whatever states.loading stored under "save" into the fresh
-- inventory/currency/skills/quests/equipment newGame() just built. An
-- unknown item id (removed in a later patch) is dropped rather than
-- crashing -- Items is guaranteed loaded by the time this runs, since
-- Play:enter loads it before newGame(). Skill and quest entries are copied
-- rather than aliased, the same precaution the inventory loop below already
-- takes, so mutating self.skills/self.quests during play can't reach back
-- into the cached save data.
function Play:loadProgress()
    local save = Assets.get("save")
    if not save then return end

    self.currency = save.currency

    for id, entry in pairs(save.skills) do
        self.skills[id] = { xp = entry.xp }
    end

    for id, entry in pairs(save.quests) do
        self.quests[id] = { progress = entry.progress, complete = entry.complete }
    end

    for key, value in pairs(save.stats) do
        self.stats[key] = value
    end

    for i, slot in ipairs(save.inventory) do
        if slot and Game.Items.get(slot.id) then
            self.inventory:put(i, { id = slot.id, count = slot.count })
        end
    end

    -- re-validated against the item registry here rather than in
    -- core/save.lua, same reasoning as the inventory loop above -- and
    -- against the item's own current `slot`, in case a later patch
    -- repurposes the id to something no longer equippable there
    for slotName, itemId in pairs(save.equipped) do
        if Game.Items.get(itemId) and Game.Items.slot(itemId) == slotName then
            self.player.equipped[slotName] = itemId
        end
    end
end

--- everything Save.save actually writes. Slots are written 1..INVENTORY_SLOTS
-- with `false` standing in for an empty one, never a hole -- see
-- utils/luaSerialize.lua's header for why a hole can't round-trip.
---@return table
function Play:snapshot()
    local slots = {}
    for i = 1, INVENTORY_SLOTS do
        local slot = self.inventory:get(i)
        slots[i] = slot and { id = slot.id, count = slot.count } or false
    end
    return {
        currency = self.currency,
        inventory = slots,
        skills = self.skills,
        quests = self.quests,
        equipped = self.player.equipped,
        stats = self.stats,
    }
end

--- writes the current run to disk; called on quitting to the main menu and,
-- generically, on closing the app (see main.lua's love.quit). Safe to call
-- before a run has ever started.
function Play:persist()
    if not self.inventory then return end
    Save.save(self:snapshot())
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
    Game.Npcs.load()
    Game.Items.load()
    Game.Skills.load()
    Game.Areas.load()
    Game.Shops.load()
    Game.Quests.load()
    self:buildOverlays()

    if not self.world or previousName == "mainMenu" then
        self:newGame()
    end

    self:layout()
end

--- call on resize; the world itself needs none
function Play:layout()
    self.pause:layout()
    self.bag:layout()
    self.shop:layout()
    self.dialog:layout()
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

--- one enemy at a time, on a timer, just outside the view and under the cap.
-- Resolved against wherever the roll actually lands, not the player's own
-- position -- a spawn point that lands in a noSpawn band (the Hub, or the
-- peaceful ring around it) skips this outright, and one that lands in the
-- Wastes only ever produces grunts, the Ashlands only cinders (see
-- Areas.at).
---@param dt number
---@param offscreen number # distance from the player to the corner of the view
function Play:spawnStep(dt, offscreen)
    if self.enemyManager:count() >= ENEMY_CAP then return end

    self.spawnTimer = self.spawnTimer + dt
    if self.spawnTimer < SPAWN_INTERVAL then return end
    self.spawnTimer = 0

    local x, y = Math.polar(self.player.x, self.player.y, Math.randAngle(),
        Math.randRange(offscreen * SPAWN_NEAR, offscreen * SPAWN_FAR))

    local area = Game.Areas.at(x, y)
    if area.noSpawn then return end

    self.enemyManager:spawnRandom(x, y, area.enemyTable)
end

--- everything a kill leaves behind goes straight to the bag; there are no
-- ground items yet, so this is where loot enters the game. A rolled drop
-- whose item carries a `requires` the player doesn't clear yet is dropped on
-- the floor of the roll -- it still rolls (so nothing about drop odds
-- changes once the requirement is met), it just never reaches the bag.
-- Combat is the only skill anything grants XP for today; a kill grants it
-- regardless of loot, since dying to something is proof enough of the fight.
-- This is also the one place both quest objective types get checked -- a
-- "collect" quest against whatever just landed in the bag, a "kill" quest
-- against the kill itself.
---@param enemy Enemy
function Play:collect(enemy)
    local gathered = 0
    for _, drop in ipairs(Game.Enemies.rollDrops(enemy.spec)) do
        local spec = Game.Items.get(drop.id)
        if spec and Game.Skills.meets(self.skills, spec.requires) then
            -- add() hands back what wouldn't fit, so a full bag counts only
            -- what actually landed
            gathered = gathered + drop.count - self.inventory:add(drop.id, drop.count)
            Game.Quests.checkObjective(self.quests, "collect", drop.id, self.inventory:count(drop.id))
        end
    end

    self.stats.kills = self.stats.kills + 1
    self.stats.itemsGathered = self.stats.itemsGathered + gathered
    self.currency = self.currency + (enemy.spec.currencyReward or DEFAULT_KILL_CURRENCY)
    Game.Skills.grantXp(self.skills, "combat", enemy.spec.xpReward or DEFAULT_KILL_XP)
    Game.Quests.checkObjective(self.quests, "kill", enemy.spec.id, 1)
end

--- the consequence is deliberately minimal and easy to change later: full hp,
-- back at the world origin -- which is the Hub's own center, so death
-- already returns the player home -- and a clean slate of enemies so
-- respawning isn't an immediate second death. Losing items/currency on
-- death is an open design decision (see PLAN.md's "Death consequences
-- finalized" and "Open Design Decisions" sections) and isn't implemented
-- here -- keeping everything is the safer default until that's actually
-- decided.
function Play:onPlayerDeath()
    self.player:respawn(0, 0)
    self:resetEnemies()
    self.camera:snapTo(self.player.x, self.player.y)
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
    if self.bag:isOpen() or self.pause:isOpen() or self.shop:isOpen() then return end
    if not self.player.aimPinned then return end
    if not love.window.hasFocus() then return end

    love.mouse.setPosition(self.camera:toScreen(self.player.aimX, self.player.aimY))
end

--- the area whose radius band the player is currently standing in -- see
-- game/areas.lua's Areas.at; always returns a spec, never nil
---@return table
function Play:currentBiome()
    return Game.Areas.at(self.player.x, self.player.y)
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

--- the nearest live NPC within talking distance, or nil. Mirrors the
-- radius-aware reach Enemy:attackPlayer uses (body-to-body plus a fixed
-- gap), not a flat pixel radius, so a bigger NPC is reachable from further
-- out.
---@return Npc|nil
function Play:findNearbyNpc()
    local player = self.player
    local nearest, nearestDistance
    for _, npc in ipairs(self.npcManager.list) do
        local distance = player:distanceTo(npc)
        if distance <= player.radius + npc.radius + INTERACT_GAP
            and (not nearestDistance or distance < nearestDistance) then
            nearest, nearestDistance = npc, distance
        end
    end
    return nearest
end

--- true while `npc` is still within talking distance -- the same test
-- findNearbyNpc uses, checked against one specific NPC rather than
-- whichever is nearest, so the shop panel only auto-closes once the NPC it
-- was actually opened for is the one left behind
---@param npc Npc
---@return boolean
function Play:withinInteractRange(npc)
    return self.player:distanceTo(npc) <= self.player.radius + npc.radius + INTERACT_GAP
end

--- opens whatever panel the nearby NPC's spec names; an `interaction` this
-- doesn't recognize (or none at all) does nothing, same as a swing that
-- finds no target
function Play:interact()
    local npc = self.nearbyNpc
    if not npc then return end

    if npc.spec.interaction == "shop" then
        UI.Sfx.press()
        self.player:setAttacking(false) -- movement keeps working (see Play:update); only the swing cancels
        self.interactingNpc = npc.id
        self.shop:openPanel(npc.spec.shop, Game.Npcs.name(npc.spec.id))
    elseif npc.spec.interaction == "dialogue" then
        self:openDialogue(npc)
    elseif npc.spec.interaction == "quest" then
        self:openQuest(npc)
    end
end

--- closes the shop panel; safe to call whether or not it's open
function Play:closeShop()
    self.shop:close()
    self.interactingNpc = nil
end

--- the single "Close" button both the dialogue box and every read-only quest
-- state (in progress, already turned in) share
---@return table[]
function Play:closeButton()
    return { { label = function() return I18n.t("dialog.close") end,
               onSelect = function() self.dialog:close() end } }
end

--- one line of flavor text (see game/npcs.lua's `interaction = "dialogue"`),
-- closed with a single button -- unlike the shop, this is a fully modal
-- prompt (see Play:update), since there's nothing to browse
---@param npc Npc
function Play:openDialogue(npc)
    UI.Sfx.press()
    self.player:releaseAll()

    self.dialog = UI.Dialog.new{
        title = Game.Npcs.name(npc.spec.id),
        message = I18n.t("game.dialogue." .. npc.spec.dialogue),
        buttons = self:closeButton(),
        onCancel = function() self.dialog:close() end,
    }
    self.dialog:setFocusSound(UI.Sfx.focus)
    self.dialog:openDialog()
end

--- the offer/progress/thanks line for a quest-giver's dialog, per
-- Game.Quests' three states -- see game/quests.lua's header for why
-- "collect" reads live inventory rather than the persisted `progress`.
-- "kill" quests use their own generic offer/progress/done strings (no item
-- to name, so no need for one -- see game/quests/cullGrunts.lua) rather
-- than sharing "collect"'s `{item}`-shaped ones.
---@param spec table # a game/quests/*.lua spec
---@return string
function Play:questMessage(spec)
    local objective = spec.objective

    if objective.type == "kill" then
        if Game.Quests.isComplete(self.quests, spec.id) then
            return I18n.t("game.quest.doneKill")
        end
        if not Game.Quests.isAccepted(self.quests, spec.id) then
            return I18n.t("game.quest.offerKill", { count = objective.count })
        end
        return I18n.t("game.quest.progressKill",
            { progress = Game.Quests.progressOf(self.quests, spec.id), count = objective.count })
    end

    if Game.Quests.isComplete(self.quests, spec.id) then
        return I18n.t("game.quest.done")
    end

    local itemName = Game.Items.name(objective.item)
    if not Game.Quests.isAccepted(self.quests, spec.id) then
        return I18n.t("game.quest.offer", { item = itemName, count = objective.count })
    end

    local progress = math.min(self.inventory:count(objective.item), objective.count)
    return I18n.t("game.quest.progress", { item = itemName, progress = progress, count = objective.count })
end

--- not-yet-accepted offers Decline/Accept, a ready one offers Turn In,
-- anything else (in progress, already turned in) just offers Close -- one
-- dialog built fresh per state rather than one reused box with swappable
-- buttons, since Dialog's button row is fixed at construction
---@param npc Npc
function Play:openQuest(npc)
    local spec = Game.Quests.get(npc.spec.quest)
    if not spec then return end

    UI.Sfx.press()
    self.player:releaseAll()

    local buttons
    if not Game.Quests.isAccepted(self.quests, spec.id) then
        buttons = {
            { label = function() return I18n.t("game.quest.decline") end,
              onSelect = function() self.dialog:close() end },
            { label = function() return I18n.t("game.quest.accept") end,
              onSelect = function()
                  Game.Quests.accept(self.quests, spec.id)
                  self.dialog:close()
              end },
        }
    elseif Game.Quests.ready(self.quests, self.inventory, spec.id) then
        buttons = { { label = function() return I18n.t("game.quest.turnIn") end,
                      onSelect = function() self:turnInQuest(spec) end } }
    else
        buttons = self:closeButton()
    end

    self.dialog = UI.Dialog.new{
        title = Game.Npcs.name(npc.spec.id),
        message = self:questMessage(spec), -- static: nothing changes while a modal dialog is open
        buttons = buttons,
        onCancel = function() self.dialog:close() end,
    }
    self.dialog:setFocusSound(UI.Sfx.focus)
    self.dialog:openDialog()
end

--- pays a "collect" objective's cost (Quests.ready already confirmed the
-- player can afford it), grants the reward, and marks the quest turned in
---@param spec table # a game/quests/*.lua spec
function Play:turnInQuest(spec)
    if spec.objective.type == "collect" then
        self.inventory:removeCount(spec.objective.item, spec.objective.count)
    end

    local reward = spec.reward or {}
    if reward.currency then self.currency = self.currency + reward.currency end
    if reward.xp then Game.Skills.grantXp(self.skills, reward.xp.skill, reward.xp.amount) end
    for _, item in ipairs(reward.items or {}) do
        self.inventory:add(item.id, item.count)
    end

    Game.Quests.complete(self.quests, spec.id)
    UI.Sfx.select()
    self.dialog:close()
end

--- the whole run: aim, player, enemies, the loot and particles a kill leaves,
-- spawning, and the camera. Both kinds of pause, and the modal dialog box,
-- all return before any of it.
---@param dt number
function Play:update(dt)
    if self.pause:isOpen() then
        self.pause:update(dt)
        return
    end
    if self.dialog:isOpen() then
        self.dialog:update(dt)
        return
    end
    if self.quietPause then return end

    self.stats.playtime = self.stats.playtime + dt -- past every pause/modal, so only live play counts

    local ctx, player = self.ctx, self.player
    if self.bag:isOpen() or self.shop:isOpen() then
        ctx.pointerX, ctx.pointerY = player.aimX, player.aimY
    else
        ctx.pointerX, ctx.pointerY = self.camera:toWorld(love.mouse.getPosition())
    end

    player:update(dt, ctx)
    self:tetherPointer() -- after the aim is final, so a walking player drags it along

    -- unlike the bag, the shop doesn't take the player's hands off movement
    -- (see Play:keypressed) -- walking far enough from the NPC it's open for
    -- closes it on its own, so this has to keep checking every frame
    self.nearbyNpc = self:findNearbyNpc()
    if self.shop:isOpen() then
        local npc = self.npcManager:get(self.interactingNpc)
        if not npc or not self:withinInteractRange(npc) then self:closeShop() end
    end

    self.npcManager:update(dt, ctx)

    local offscreen = Math.length(self.camera:halfExtents())
    local despawnAt = offscreen * DESPAWN

    self.enemyManager:update(dt, ctx)
    for _, enemy in ipairs(self.enemyManager:prune(player, despawnAt)) do
        self.deaths:spawn(enemy.x, enemy:drawY(), enemy.color)
        self:collect(enemy)
    end

    if player.dead then self:onPlayerDeath() end
    Game.Hud.update(dt, player)

    self.deaths:update(dt)
    self:spawnStep(dt, offscreen)

    -- only the Hub's own spec sets `bounds` -- everywhere else this is nil,
    -- which is exactly "follow unclamped," the same as an open wilderness
    -- always has
    self.camera:follow(player.x, player.y, dt, self:currentBiome().bounds)
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

--- routed by what's open: the pause menu and the dialog box take everything,
-- the inventory takes only its own close keys, and otherwise it reaches the
-- player
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

    if self.dialog:isOpen() then
        self.dialog:keypressed(key)
        return
    end

    if self.bag:isOpen() then
        if key == "escape" or key == INVENTORY_KEY then self:toggleInventory() end
        return
    end

    -- unlike the bag, movement still reaches the player below: walking away
    -- from the NPC is a valid way to end the conversation (see Play:update)
    if self.shop:isOpen() then
        if key == "escape" then self:closeShop() end
        self.player:keypressed(key)
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
    if key == INTERACT_KEY and self.nearbyNpc then
        self:interact()
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
    if self.dialog:isOpen() then self.dialog:mousemoved(x, y) end
    if self.bag:isOpen() then self.bag:mousemoved(x, y) end
    if self.shop:isOpen() then self.shop:mousemoved(x, y) end
end

---@param x number
---@param y number
---@param button integer
function Play:mousepressed(x, y, button)
    if self.pause:isOpen() then
        self.pause:mousepressed(x, y, button)
        return
    end
    if self.dialog:isOpen() then
        self.dialog:mousepressed(x, y, button)
        return
    end
    if self.bag:isOpen() then
        self.bag:mousepressed(x, y, button)
        return
    end
    if self.shop:isOpen() then
        self.shop:mousepressed(x, y, button)
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
    if self.dialog:isOpen() then
        self.dialog:mousereleased(x, y, button)
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
    if self.dialog:isOpen() then
        UI.Cursor.setHover(self.dialog:hovering(love.mouse.getPosition()))
        return
    end
    if self.bag:isOpen() then
        UI.Cursor.setHover(self.bag.hovered ~= nil)
        return
    end
    if self.shop:isOpen() then
        UI.Cursor.setHover(self.shop:hoveredAffordable())
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
    for _, npc in ipairs(self.npcManager.list) do list[#list + 1] = npc end
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

    -- every overlay takes the screen while it's up (each draws its own scrim),
    -- so the HUD and the hint row go with them
    if not self.bag:isOpen() and not self.pause:isOpen() and not self.shop:isOpen()
        and not self.dialog:isOpen() then
        Game.Hud.draw(self.player, self.currency, self.skills)

        if self.nearbyNpc then
            UI.Label.hint(I18n.t("game.npc.interactHint",
                { key = INTERACT_KEY:upper(), name = Game.Npcs.name(self.nearbyNpc.spec.id) }), true)
        else
            UI.Label.hint(I18n.t("game.hint"), true)
        end
    end
    if self.bag:isOpen() then self.bag:draw() end
    if self.pause:isOpen() then self.pause:draw() end
    if self.shop:isOpen() then self.shop:draw() end
    if self.dialog:isOpen() then self.dialog:draw() end

    if Game.DebugOverlay.visible then
        self.ctx.pauseState = self.pause:isOpen() and "pause menu"
            or self.dialog:isOpen() and "dialog"
            or self.quietPause and "paused (F3+P)" or "running"
        Game.DebugOverlay.drawScreen(self.ctx)
    end

    self:drawCursor()
end

return Play
