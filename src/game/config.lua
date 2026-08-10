-- src/game/config.lua
-- Every tunable number the game runs on, in one file. Nothing here draws, reads
-- input, or holds run state — it is pure data, so balancing the game means
-- editing this file and nothing else.
--
-- Two conventions the whole simulation depends on:
--
--   * Distances are in TILES, never pixels. The simulation never learns how big
--     a tile is on screen (see src/game/renderer.lua, which owns that), so the
--     balance below means the same thing at every resolution.
--   * Speeds are per second. dt is real seconds; nothing is per-frame.
--
-- Per-level growth is expressed as a multiplier compounded `level - 1` times,
-- so a tower's stats are a function of its level rather than a stored snapshot.
-- That is what lets a rebalance apply to towers that are already built and
-- already saved (see World:refresh).

local Config = {}

-- How far a tower can be upgraded. Level 1 is the tower as built.
Config.maxLevel = 5

Config.economy = {
    startingGold  = 120,
    startingLives = 20,
    -- Fraction of everything spent on a tower (build + every upgrade) that
    -- selling gives back. Below 1 so repositioning costs something.
    sellRefund    = 0.6,
    -- Running out of lives doesn't end the game — it knocks the wave counter
    -- back to this fraction of where it was and refills lives. Towers and gold
    -- survive. An idle game needs a wall the player can retry against on its
    -- own, not a loss screen that throws the session away.
    setbackKeep   = 0.7,
}

Config.waves = {
    -- Seconds of quiet between waves when the player does nothing at all. This
    -- is the idle pace: leave the game running and it clears waves by itself.
    intermission   = 14,
    -- Longer breather after a setback, so the player can spend before the next
    -- wave lands on the defences that just failed.
    setbackGrace   = 25,
    spawnInterval  = 0.65, -- seconds between enemies inside one wave
    baseCount      = 6,    -- enemies in wave 1
    countGrowth    = 0.55, -- additional enemies per wave, linear
    maxCount       = 40,   -- clamp, so a late wave stays a wave and not a screen of dots
    bossEvery      = 10,
    -- Calling a wave early pays out the intermission the player gave up, at
    -- this many gold per second skipped. The active/idle trade in one number:
    -- waiting is free, attention is worth gold.
    callBonusPerSecond = 4,
}

Config.enemies = {
    baseHealth   = 22,
    healthGrowth = 1.125, -- per wave, compounding — the difficulty curve
    baseSpeed    = 1.6,   -- tiles per second
    speedGrowth  = 1.008,
    maxSpeed     = 3.2,   -- clamp: past this, towers can't track at all
    baseBounty   = 6,
    bountyGrowth = 1.07,  -- deliberately below healthGrowth, so income has to
                          -- come from more kills rather than richer ones
    leakDamage   = 1,     -- lives lost per enemy that reaches the exit

    -- The wave-multiple-of-bossEvery enemy, as multipliers on the wave's
    -- ordinary stats. Slower and far tougher: a boss is a damage check, and it
    -- has to stay in range long enough to be one.
    boss = { health = 9, bounty = 12, speed = 0.62, size = 1.7 },

    -- Drawn radius in tiles (see renderer). Here rather than in the renderer
    -- because it is also the hit radius the simulation blasts against.
    size = 0.28,
}

-- Held gold does nothing on its own, so time away is paid out against what the
-- run has actually been earning (World.stats), not against a flat rate. A fresh
-- save with no income earns nothing, which is correct.
Config.offline = {
    maxHours   = 4,    -- beyond this, time away stops counting
    rate       = 0.35, -- fraction of the run's live gold/sec granted while away
    minSeconds = 60,   -- shorter gaps are ignored rather than reported
}

-- The active ability: a burst of fire rate on a long cooldown. Being at the
-- keyboard should be worth more than not being there, and this is the cheapest
-- honest way to say so.
Config.overcharge = {
    duration      = 6,
    cooldown      = 45,  -- begins when the burst ends
    fireRateBonus = 2.0, -- multiplier on every tower's fire rate
}

-- The towers, in build-bar order.
--
--   id       : save key and locale key (game.tower.<id>)
--   icon     : a src/ui/glyph name
--   cost     : gold to build at level 1
--   damage   : per shot
--   range    : tiles, measured from the tower's tile center
--   fireRate : shots per second
--   speed    : projectile travel, tiles per second
--   blast    : radius in tiles a shot damages within
--   targets  : how many enemies one shot may hit (1 = single target)
--   slow     : optional { factor, duration } applied on hit
--   growth   : per-level multipliers, compounded (level - 1) times.
--              `cost` is the odd one out — it multiplies the BUILD cost to
--              price the next upgrade (see World:upgradeCost).
--
-- A fourth tower type is a new entry here plus three locale strings. Nothing
-- else in the game enumerates tower types.
Config.towers = {
    {
        id = "gun", icon = "crosshair",
        cost = 60,
        damage = 7, range = 2.6, fireRate = 1.9, speed = 14,
        blast = 0.3, targets = 1,
        growth = { cost = 1.65, damage = 1.35, range = 1.06, fireRate = 1.10 },
    },
    {
        id = "frost", icon = "frost",
        cost = 95,
        damage = 3, range = 2.4, fireRate = 1.2, speed = 11,
        blast = 0.55, targets = 2,
        slow = { factor = 0.55, duration = 1.8 },
        growth = { cost = 1.6, damage = 1.30, range = 1.06, fireRate = 1.08,
                   slowDuration = 1.08 },
    },
    {
        id = "cannon", icon = "flame",
        cost = 130,
        damage = 16, range = 2.2, fireRate = 0.75, speed = 9,
        blast = 0.9, targets = math.huge,
        growth = { cost = 1.70, damage = 1.40, range = 1.05, fireRate = 1.08,
                   blast = 1.06 },
    },
}

-- id -> definition, for the save file and for tower lookups.
Config.towerById = {}
for index, def in ipairs(Config.towers) do
    def.index = index
    Config.towerById[def.id] = def
end

-- Enemy stats for a given wave. Bosses are the same curve with the boss
-- multipliers on top, so they scale with the run instead of being authored.
function Config.enemyStats(wave, boss)
    local e = Config.enemies
    local n = math.max(0, wave - 1)

    local health = e.baseHealth * e.healthGrowth ^ n
    local bounty = e.baseBounty * e.bountyGrowth ^ n
    local speed = math.min(e.maxSpeed, e.baseSpeed * e.speedGrowth ^ n)
    local size = e.size

    if boss then
        health = health * e.boss.health
        bounty = bounty * e.boss.bounty
        speed = speed * e.boss.speed
        size = size * e.boss.size
    end

    return {
        health = health,
        bounty = math.floor(bounty),
        speed = speed,
        size = size,
        boss = boss or false,
    }
end

-- How many enemies wave `n` sends, boss excluded.
function Config.waveCount(wave)
    local w = Config.waves
    return math.min(w.maxCount, math.floor(w.baseCount + w.countGrowth * (wave - 1)))
end

function Config.isBossWave(wave)
    return wave > 0 and wave % Config.waves.bossEvery == 0
end

return Config
