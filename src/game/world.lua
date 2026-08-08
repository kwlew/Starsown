-- src/game/world.lua
-- The simulation. Owns the economy, the towers, the enemies in flight and the
-- wave schedule, and advances all of it from dt.
--
-- It draws nothing and reads no input: there is not a single love.graphics or
-- love.mouse call in this file. Everything is in grid space (see map.lua), so
-- the world behaves identically at every resolution, runs with no window at all,
-- and can be stepped faster than real time — which is exactly what makes the
-- offline catch-up in src/game/save.lua possible.
--
--   local world = World.new()
--   world.onKill = function(enemy) ... end   -- optional event hooks
--   world:update(dt)
--   world:build(col, row, "gun")             -- -> true, or false + reason
--
-- Events are plain optional callbacks rather than a subscription system: there
-- is exactly one listener for each (the game state, which forwards to the
-- renderer and the audio), and a nil check is the whole implementation.
--
--   onKill(enemy)            an enemy died — enemy.x/.y is where
--   onLeak(enemy)            an enemy reached the exit
--   onWaveStart(wave, boss)  a wave began
--   onSetback(wave)          lives ran out; the run fell back to `wave`
--   onBuild(tower)           a tower was placed or upgraded

local Config = require "game.config"
local Map = require "game.map"

local World = {}
World.__index = World

-- Enemies and projectiles are flagged `dead` and swept at the end of the frame
-- rather than removed as they die: a projectile detonating mid-iteration would
-- otherwise be mutating the very list the loop is walking.
local function compact(list)
    local kept = 0
    for i = 1, #list do
        local item = list[i]
        if not item.dead then
            kept = kept + 1
            list[kept] = item
        end
    end
    for i = #list, kept + 1, -1 do
        list[i] = nil
    end
end

local function tileKey(col, row)
    return row * (Map.COLS + 2) + col
end

--------------------------------------------------------------------------------
-- Construction and run state
--------------------------------------------------------------------------------

function World.new()
    local self = setmetatable({}, World)
    self:reset()
    return self
end

function World:reset()
    self.gold = Config.economy.startingGold
    self.lives = Config.economy.startingLives
    self.wave = 0
    self.bestWave = 0

    self.enemies = {}
    self.towers = {}
    self.projectiles = {}
    self.occupied = {} -- tileKey -> tower

    -- "intermission" (counting down to the next wave) | "spawning" (feeding
    -- enemies in) | "clearing" (all sent, waiting for the board to empty).
    self.phase = "intermission"
    self.phaseTimer = Config.waves.intermission
    self.phaseDuration = Config.waves.intermission -- what the timer started at
    self.pending = 0    -- enemies still to spawn this wave, boss included
    self.waveTotal = 0  -- what `pending` started at, for the progress readout
    self.spawnTimer = 0

    self.overcharge = { active = 0, cooldown = 0 }

    -- What the offline payout is computed against, and what a stats screen
    -- would read. `elapsed` is time simulated, not wall-clock time, and
    -- `goldEarned` counts only what towers shot down — see stats.offlineGold,
    -- which is deliberately kept out of the rate it would otherwise feed.
    self.stats = {
        elapsed = 0, goldEarned = 0, offlineGold = 0,
        kills = 0, leaks = 0, built = 0,
    }
end

--------------------------------------------------------------------------------
-- Tower stats
--
-- Derived from the level every time rather than stored, so a balance change in
-- config.lua reaches towers that were built before it — including towers loaded
-- from a save. Cached on the tower and refreshed only when its level changes,
-- since the alternative is a handful of pow() calls per tower per frame.
--------------------------------------------------------------------------------

function World:refresh(tower)
    local def = Config.towerById[tower.type]
    local g = def.growth
    local n = tower.level - 1

    tower.damage = def.damage * g.damage ^ n
    tower.range = def.range * g.range ^ n
    tower.fireRate = def.fireRate * g.fireRate ^ n
    tower.blast = def.blast * (g.blast or 1) ^ n
    tower.targets = def.targets
    tower.speed = def.speed

    if def.slow then
        tower.slow = {
            factor = def.slow.factor,
            duration = def.slow.duration * (g.slowDuration or 1) ^ n,
        }
    else
        tower.slow = nil
    end
end

-- Damage per second on paper, for the tower panel. Overcharge is deliberately
-- excluded: this is the tower's own number, not what it happens to be doing in
-- this instant.
function World:towerDps(tower)
    return tower.damage * tower.fireRate
end

-- Gold to take `tower` to its next level, or nil at max. Priced off the BUILD
-- cost so the ladder is set by the tower's class rather than by what the last
-- upgrade happened to cost.
function World:upgradeCost(tower)
    if tower.level >= Config.maxLevel then return nil end
    local def = Config.towerById[tower.type]
    return math.floor(def.cost * def.growth.cost ^ tower.level)
end

function World:sellValue(tower)
    return math.floor(tower.spent * Config.economy.sellRefund)
end

--------------------------------------------------------------------------------
-- Player actions
--
-- Each returns true on success, or false plus a reason key the HUD can show.
-- Validating here rather than in the UI is what keeps the rules in one place:
-- a keyboard shortcut, a click, and a future auto-builder all get the same
-- answer.
--------------------------------------------------------------------------------

function World:towerAt(col, row)
    return self.occupied[tileKey(col, row)]
end

function World:canBuild(col, row, typeId)
    local def = Config.towerById[typeId]
    if not def then return false, "unknownType" end
    if not Map.isBuildable(col, row) then return false, "blocked" end
    if self:towerAt(col, row) then return false, "occupied" end
    if self.gold < def.cost then return false, "poor" end
    return true
end

function World:build(col, row, typeId)
    local ok, reason = self:canBuild(col, row, typeId)
    if not ok then return false, reason end

    local def = Config.towerById[typeId]
    local tower = {
        type = typeId,
        col = col, row = row,
        level = 1,
        spent = def.cost, -- what a sale refunds against
        cooldown = 0,     -- seconds until it may fire again
        angle = 0,        -- last facing, so the barrel points at its target
        kills = 0,
    }
    self:refresh(tower)

    self.gold = self.gold - def.cost
    self.towers[#self.towers + 1] = tower
    self.occupied[tileKey(col, row)] = tower
    self.stats.built = self.stats.built + 1

    if self.onBuild then self.onBuild(tower) end
    return true, nil, tower
end

function World:upgrade(tower)
    local cost = self:upgradeCost(tower)
    if not cost then return false, "maxLevel" end
    if self.gold < cost then return false, "poor" end

    self.gold = self.gold - cost
    tower.spent = tower.spent + cost
    tower.level = tower.level + 1
    self:refresh(tower)

    if self.onBuild then self.onBuild(tower) end
    return true
end

function World:sell(tower)
    local refund = self:sellValue(tower)
    self.gold = self.gold + refund

    self.occupied[tileKey(tower.col, tower.row)] = nil
    for i = #self.towers, 1, -1 do
        if self.towers[i] == tower then
            table.remove(self.towers, i)
            break
        end
    end

    -- Shots already in flight from a sold tower keep going. They were paid for.
    return true, nil, refund
end

-- Skips the rest of the intermission and pays out the time given up. Only
-- legal during an intermission — there is nothing to call while a wave is
-- already on the board.
function World:callWave()
    if self.phase ~= "intermission" then return false, "notWaiting" end

    local bonus = math.floor(math.max(0, self.phaseTimer) * Config.waves.callBonusPerSecond)
    self.gold = self.gold + bonus
    self.stats.goldEarned = self.stats.goldEarned + bonus
    self:startWave()
    return true, nil, bonus
end

function World:callBonus()
    if self.phase ~= "intermission" then return 0 end
    return math.floor(math.max(0, self.phaseTimer) * Config.waves.callBonusPerSecond)
end

function World:canOvercharge()
    return self.overcharge.cooldown <= 0
end

function World:triggerOvercharge()
    if not self:canOvercharge() then return false, "cooling" end
    local o = Config.overcharge
    self.overcharge.active = o.duration
    -- The cooldown covers the burst as well, so "ready again" is measured from
    -- when the burst ends rather than from when it started.
    self.overcharge.cooldown = o.duration + o.cooldown
    return true
end

-- The live multiplier on every tower's fire rate.
function World:fireRateMultiplier()
    return self.overcharge.active > 0 and Config.overcharge.fireRateBonus or 1
end

--------------------------------------------------------------------------------
-- Waves
--------------------------------------------------------------------------------

function World:startWave()
    self.wave = self.wave + 1
    if self.wave > self.bestWave then self.bestWave = self.wave end

    self.pending = Config.waveCount(self.wave)
    self.bossWave = Config.isBossWave(self.wave)
    if self.bossWave then self.pending = self.pending + 1 end

    self.waveTotal = self.pending
    self.spawnTimer = 0
    self.phase = "spawning"

    if self.onWaveStart then self.onWaveStart(self.wave, self.bossWave) end
end

function World:spawnEnemy()
    -- The boss is the last thing out of the gate on a boss wave, so it arrives
    -- behind its escort rather than in the middle of it.
    local boss = self.bossWave and self.pending == 1
    local stats = Config.enemyStats(self.wave, boss)

    local x, y = Map.positionAt(0)
    self.enemies[#self.enemies + 1] = {
        dist = 0,
        x = x, y = y,
        health = stats.health,
        maxHealth = stats.health,
        speed = stats.speed,
        bounty = stats.bounty,
        size = stats.size,
        boss = stats.boss,
        slowFor = 0,      -- seconds of slow remaining
        slowFactor = 1,   -- speed multiplier while slowed
    }

    self.pending = self.pending - 1
end

function World:updateWaves(dt)
    if self.phase == "intermission" then
        self.phaseTimer = self.phaseTimer - dt
        if self.phaseTimer <= 0 then self:startWave() end

    elseif self.phase == "spawning" then
        self.spawnTimer = self.spawnTimer - dt
        -- A while loop rather than an if: a long dt (a stutter, or the offline
        -- catch-up stepping in big slices) must release every enemy it covers,
        -- not one per call.
        while self.pending > 0 and self.spawnTimer <= 0 do
            self:spawnEnemy()
            self.spawnTimer = self.spawnTimer + Config.waves.spawnInterval
        end
        if self.pending <= 0 then self.phase = "clearing" end

    else -- clearing
        if #self.enemies == 0 then
            self.phase = "intermission"
            self.phaseTimer = Config.waves.intermission
            self.phaseDuration = Config.waves.intermission
        end
    end
end

-- How far the current phase has got, 0..1, for the HUD's one progress bar.
-- Computed here rather than in the HUD because only the world knows what the
-- timer started at and how many enemies the wave was worth.
function World:waveProgress()
    if self.phase == "intermission" then
        if self.phaseDuration <= 0 then return 1 end
        return 1 - math.max(0, self.phaseTimer) / self.phaseDuration
    end

    if self.waveTotal <= 0 then return 0 end
    -- Sent and dealt with, over the size of the wave: it keeps advancing across
    -- the hand-off from spawning to clearing instead of restarting at zero.
    local settled = self.waveTotal - self.pending - #self.enemies
    return math.max(0, math.min(1, settled / self.waveTotal))
end

-- Lives ran out. The run falls back rather than ending: towers, gold and the
-- best-wave record all survive, and the wave counter drops to somewhere the
-- current defences can hold. That gives an idle game a wall the player can grind
-- against unattended instead of a loss screen that throws the session away.
function World:setback()
    self.wave = math.max(0, math.floor(self.wave * Config.economy.setbackKeep))
    self.lives = Config.economy.startingLives

    for _, enemy in ipairs(self.enemies) do
        enemy.dead = true
    end
    for _, projectile in ipairs(self.projectiles) do
        projectile.dead = true
    end

    self.pending = 0
    self.phase = "intermission"
    self.phaseTimer = Config.waves.setbackGrace
    self.phaseDuration = Config.waves.setbackGrace

    if self.onSetback then self.onSetback(self.wave) end
end

--------------------------------------------------------------------------------
-- Enemies
--------------------------------------------------------------------------------

function World:damage(enemy, amount)
    if enemy.dead then return end

    enemy.health = enemy.health - amount
    if enemy.health > 0 then return end

    enemy.dead = true
    self.gold = self.gold + enemy.bounty
    self.stats.goldEarned = self.stats.goldEarned + enemy.bounty
    self.stats.kills = self.stats.kills + 1

    if self.onKill then self.onKill(enemy) end
end

local function applySlow(enemy, slow)
    -- The strongest slow wins and refreshes the timer, rather than stacking:
    -- stacking multiplies to a standstill the moment two frost towers overlap.
    if slow.factor < enemy.slowFactor or enemy.slowFor <= 0 then
        enemy.slowFactor = slow.factor
    end
    enemy.slowFor = math.max(enemy.slowFor, slow.duration)
end

function World:updateEnemies(dt)
    local leaked = false

    for _, enemy in ipairs(self.enemies) do
        if not enemy.dead then
            if enemy.slowFor > 0 then
                enemy.slowFor = enemy.slowFor - dt
                if enemy.slowFor <= 0 then enemy.slowFactor = 1 end
            end

            enemy.dist = enemy.dist + enemy.speed * enemy.slowFactor * dt
            enemy.x, enemy.y = Map.positionAt(enemy.dist)

            if enemy.dist >= Map.length then
                enemy.dead = true
                enemy.leaked = true
                self.lives = self.lives - Config.enemies.leakDamage
                self.stats.leaks = self.stats.leaks + 1
                leaked = true
                if self.onLeak then self.onLeak(enemy) end
            end
        end
    end

    -- Checked once after the loop, not inside it: a setback marks every enemy
    -- dead, and doing that partway through the iteration would have the rest of
    -- this frame's movement applied to enemies that no longer exist.
    if leaked and self.lives <= 0 then
        self:setback()
    end
end

--------------------------------------------------------------------------------
-- Towers and projectiles
--------------------------------------------------------------------------------

-- The enemy furthest along the path within `tower`'s range — the standard "first"
-- targeting rule, and the right default: the enemy closest to the exit is the
-- one about to cost a life. Distance along the path is already a scalar, so
-- picking it is a comparison rather than a sort.
function World:findTarget(tower)
    local best, bestDist
    local rangeSq = tower.range * tower.range

    for _, enemy in ipairs(self.enemies) do
        if not enemy.dead and (not bestDist or enemy.dist > bestDist) then
            local dx, dy = enemy.x - tower.col, enemy.y - tower.row
            if dx * dx + dy * dy <= rangeSq then
                best, bestDist = enemy, enemy.dist
            end
        end
    end

    return best
end

function World:fire(tower, target)
    self.projectiles[#self.projectiles + 1] = {
        x = tower.col, y = tower.row,
        tx = target.x, ty = target.y, -- last known position, if the target dies
        target = target,
        speed = tower.speed,
        damage = tower.damage,
        blast = tower.blast,
        targets = tower.targets,
        slow = tower.slow,
        source = tower,
    }
end

function World:updateTowers(dt)
    local rateMultiplier = self:fireRateMultiplier()

    for _, tower in ipairs(self.towers) do
        tower.cooldown = tower.cooldown - dt * rateMultiplier

        if tower.cooldown <= 0 then
            local target = self:findTarget(tower)
            if target then
                tower.angle = math.atan2(target.y - tower.row, target.x - tower.col)
                self:fire(tower, target)
                tower.cooldown = 1 / tower.fireRate
            else
                -- Idle towers sit ready rather than banking cooldown, so a
                -- long quiet stretch doesn't let one dump a burst of free shots
                -- the moment a wave arrives.
                tower.cooldown = 0
            end
        end
    end
end

function World:detonate(projectile)
    local remaining = projectile.targets
    local blastSq = projectile.blast * projectile.blast
    local hits = 0

    local function tryHit(enemy)
        if enemy.dead or remaining <= 0 then return end
        local dx, dy = enemy.x - projectile.x, enemy.y - projectile.y
        -- The enemy's own size counts, so a big boss is hit by a shot that
        -- lands against its flank rather than only dead center.
        local reach = projectile.blast + enemy.size
        if dx * dx + dy * dy <= reach * reach then
            self:damage(enemy, projectile.damage)
            if projectile.slow then applySlow(enemy, projectile.slow) end
            -- Credited to the tower that fired, not to the shot: `damage` flags
            -- the kill, so comparing across the call is what tells them apart.
            -- The firing tower may have been sold mid-flight, hence the guard.
            if enemy.dead and projectile.source then
                projectile.source.kills = projectile.source.kills + 1
            end
            remaining = remaining - 1
            hits = hits + 1
        end
    end

    -- The intended target first, so a single-shot always lands on what it was
    -- aimed at rather than on whichever enemy the list happened to reach first.
    local intended = projectile.target
    if intended and not intended.dead then tryHit(intended) end

    if remaining > 0 then
        for _, enemy in ipairs(self.enemies) do
            if enemy ~= intended then tryHit(enemy) end
        end
    end

    -- Unused, but the one number a hit effect would want. Kept so the event
    -- below carries it rather than the renderer having to re-derive it.
    projectile.hits = hits
    if self.onImpact then self.onImpact(projectile) end
end

function World:updateProjectiles(dt)
    for _, projectile in ipairs(self.projectiles) do
        -- Home while the target lives; once it dies, keep flying to where it
        -- was. A cannon shell still lands and still splashes, which is both
        -- better-looking and fairer than a shot evaporating mid-air.
        local target = projectile.target
        if target and not target.dead then
            projectile.tx, projectile.ty = target.x, target.y
        end

        local dx, dy = projectile.tx - projectile.x, projectile.ty - projectile.y
        local distance = math.sqrt(dx * dx + dy * dy)
        local step = projectile.speed * dt

        if distance <= step or distance == 0 then
            projectile.x, projectile.y = projectile.tx, projectile.ty
            projectile.dead = true
            self:detonate(projectile)
        else
            projectile.x = projectile.x + dx / distance * step
            projectile.y = projectile.y + dy / distance * step
        end
    end
end

--------------------------------------------------------------------------------
-- The frame
--------------------------------------------------------------------------------

-- Gold only comes from kills, so a board with no towers on it can never earn
-- any — a state reachable only by selling everything, since the refund is below
-- the build cost. Rather than leave the run soft-locked with no way forward,
-- float the player back up to the cheapest tower. Costs nothing in a run that
-- never gets there.
local cheapestTower
function World:breakDeadlock()
    if #self.towers > 0 then return end

    if not cheapestTower then
        cheapestTower = math.huge
        for _, def in ipairs(Config.towers) do
            cheapestTower = math.min(cheapestTower, def.cost)
        end
    end

    if self.gold < cheapestTower then self.gold = cheapestTower end
end

function World:update(dt)
    self.stats.elapsed = self.stats.elapsed + dt

    local o = self.overcharge
    if o.active > 0 then o.active = math.max(0, o.active - dt) end
    if o.cooldown > 0 then o.cooldown = math.max(0, o.cooldown - dt) end

    self:updateWaves(dt)
    self:updateEnemies(dt)
    self:updateTowers(dt)
    self:updateProjectiles(dt)

    compact(self.enemies)
    compact(self.projectiles)

    self:breakDeadlock()
end

-- Average gold per second across the whole run. What the offline payout is
-- computed against (see save.lua): a run that has never earned anything earns
-- nothing while away, which is the honest answer.
function World:goldPerSecond()
    if self.stats.elapsed <= 0 then return 0 end
    return self.stats.goldEarned / self.stats.elapsed
end

return World
