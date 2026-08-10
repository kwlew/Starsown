-- src/states/game.lua
-- The run. Owns nothing itself: it wires the simulation (game/world.lua) to the
-- board renderer, the HUD, and the save file, and routes input between them.
--
-- The loop, in one paragraph. Waves arrive on their own and towers fight on
-- their own, so a run makes progress with nobody watching — that is the idle
-- half, and it is also what makes closing the game safe (see game/save.lua,
-- which pays out time away against what the run has been earning). The active
-- half is everything worth being present for: deciding where gold goes, calling
-- a wave early to be paid for the intermission you gave up, and spending
-- Overcharge at the moment a boss is in range. Running out of lives doesn't end
-- the run, it knocks the wave counter back — a wall to grind at rather than a
-- loss screen.
--
-- Input priority is HUD, then board: the HUD answers every event first and says
-- whether it took it, so a click on a build button can never also place a tower
-- on whatever is behind it.

local StateManager = require "core.stateManager"
local Presence = require "services.presence"
local I18n = require "core.i18n"
local Format = require "utils.format"
local UI = require "ui"

local Audio = require "core.audio"
local Audios = require "utils.audios"

local Config = require "game.config"
local World = require "game.world"
local Renderer = require "game.renderer"
local Hud = require "game.hud"
local Save = require "game.save"

local Game = {}

-- Seconds between background saves. The run is also saved on the way into the
-- pause menu and on a clean quit (see love.quit in main.lua); this is the floor
-- on what a crash or a pulled plug can cost.
local AUTOSAVE_INTERVAL = 20

-- How long a banner (offline earnings, a setback) stays up.
local NOTICE_LIFE = 6

--------------------------------------------------------------------------------
-- Run lifecycle
--------------------------------------------------------------------------------

function Game:setPresence()
    self.presenceWave = self.world.wave
    Presence.set{
        details = I18n.t("game.wave", { n = self.world.wave }),
        state = I18n.t("game.presence", { n = #self.world.towers }),
        smallText = "In game",
    }
end

-- Banner across the top of the board. Used for the two things that happen
-- without the player asking: what they earned while away, and a setback.
function Game:notify(text, color)
    self.notice = { text = text, color = color, life = NOTICE_LIFE }
end

-- The world's events, forwarded to the things that only exist to react: the
-- renderer's floating text and the UI sounds. The world itself stays free of
-- both (see game/world.lua).
function Game:wireEvents()
    local world, renderer = self.world, self.renderer

    world.onKill = function(enemy)
        renderer:floater(enemy.x, enemy.y, "+" .. Format.number(enemy.bounty),
            UI.Theme.colors.warning)
        Audio.play("sfx", Audios.clone("starExplosion"))
    end

    world.onLeak = function(enemy)
        renderer:floater(enemy.x, enemy.y, I18n.t("game.leak"), UI.Theme.colors.danger)
    end

    world.onWaveStart = function(wave, boss)
        self:setPresence()
        if boss then
            self:notify(I18n.t("game.bossWave", { n = wave }), UI.Theme.colors.warning)
        end
    end

    world.onSetback = function(wave)
        self:notify(I18n.t("game.setback", { n = wave }), UI.Theme.colors.danger)
        UI.Sfx.press()
    end
end

-- Loads the saved run, or starts a fresh one. Called on a real entry to the
-- state, never on the way back from the pause menu.
function Game:startRun()
    local world, offlineGold, offlineSeconds = Save.read()
    self.world = world or World.new()

    self.selected = nil
    self.buildType = Config.towers[1].id
    self.hoverCol, self.hoverRow = nil, nil
    self.notice = nil
    self.sinceSave = 0

    self.renderer = self.renderer or Renderer.new()
    -- Rebuilt with the world: the HUD's labels close over the run they were
    -- built for, so a new run needs a new HUD rather than a reset one.
    self.hud = Hud.new(self)

    self:wireEvents()

    if offlineGold and offlineGold > 0 then
        self:notify(I18n.t("game.offline", {
            t = Format.duration(offlineSeconds),
            n = Format.number(offlineGold),
        }), UI.Theme.colors.accent)
    end
end

function Game:save()
    if self.world then Save.write(self.world) end
end

-- For love.quit, which has no way to ask the active state whether it happens to
-- be a run. Safe to call at any time.
function Game.saveIfRunning()
    if Game.world then Save.write(Game.world) end
end

-- opts.resumed marks a return from the pause menu rather than the start of a
-- run: the world is still in memory and must not be rebuilt under it.
function Game:enter(previousName, opts)
    local resumed = type(opts) == "table" and opts.resumed

    if not resumed or not self.world then
        self:startRun()
    end

    self:setPresence()
    self.mouseX, self.mouseY = love.mouse.getPosition()
    self:layout()
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

-- The HUD claims the top and bottom strips and reports what is left; the board
-- centers itself in that. Called from enter and resize, never from draw.
function Game:layout()
    local w, h = love.graphics.getDimensions()
    local area = self.hud:layout(w, h)
    self.renderer:layout(area.x, area.y, area.w, area.h)
end

function Game:resize()
    self:layout()
end

--------------------------------------------------------------------------------
-- Player actions
--
-- Thin wrappers over the world, which owns every rule about whether an action is
-- legal. Their whole job is the feedback: a sound, a floater, a banner.
--------------------------------------------------------------------------------

-- Picking the tower already picked puts the cursor down, so the same key both
-- arms and disarms the build cursor.
function Game:selectBuild(typeId)
    UI.Sfx.select()
    self.buildType = (self.buildType == typeId) and nil or typeId
    if self.buildType then self.selected = nil end
end

function Game:tryBuild(col, row)
    local ok = self.world:build(col, row, self.buildType)
    if ok then
        UI.Sfx.select()
    else
        UI.Sfx.focus() -- a quieter blip: refused, not broken
    end
end

function Game:upgradeSelected()
    if not self.selected then return end
    if self.world:upgrade(self.selected) then
        UI.Sfx.select()
        self.renderer:floater(self.selected.col, self.selected.row - 0.5,
            I18n.t("game.level", { n = self.selected.level }), UI.Theme.colors.accent)
    end
end

function Game:sellSelected()
    if not self.selected then return end
    local tower = self.selected
    local _, _, refund = self.world:sell(tower)

    UI.Sfx.press()
    self.renderer:floater(tower.col, tower.row - 0.5,
        "+" .. Format.number(refund), UI.Theme.colors.warning)
    self.selected = nil
end

function Game:callWave()
    local ok, _, bonus = self.world:callWave()
    if not ok then return end

    UI.Sfx.select()
    -- The payout goes in the banner rather than on the board: there is no place
    -- on the map it belongs to, and it is the one number the player pressed the
    -- button for.
    if bonus > 0 then
        self:notify(I18n.t("game.called", { n = Format.number(bonus) }),
            UI.Theme.colors.warning)
    end
end

function Game:overcharge()
    if self.world:triggerOvercharge() then
        UI.Sfx.press()
        self:notify(I18n.t("game.overchargeOn"), UI.Theme.colors.accent)
    end
end

-- Esc backs out one layer at a time — the build cursor, then the selection,
-- then the run — rather than jumping straight to the pause menu from whatever
-- the player happened to be doing.
function Game:back()
    if self.buildType then
        self.buildType = nil
        return
    end
    if self.selected then
        self.selected = nil
        return
    end

    -- Saved on the way out, so "Quit to Menu" from the pause screen (which
    -- never returns here) still leaves the run on disk.
    self:save()
    StateManager.switch("pause")
end

--------------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------------

function Game:keypressed(key)
    if key == "escape" then return self:back() end
    if key == "space" then return self:callWave() end
    if key == "e" then return self:overcharge() end
    if key == "delete" or key == "backspace" then return self:sellSelected() end
    if key == "u" then return self:upgradeSelected() end

    -- Number keys pick a tower to build, in build-bar order.
    local index = tonumber(key)
    if index and Config.towers[index] then
        self:selectBuild(Config.towers[index].id)
    end
end

function Game:mousemoved(x, y)
    self.mouseX, self.mouseY = x, y
    self.hud:mousemoved(x, y)
    self.hoverCol, self.hoverRow = self.renderer:toGrid(x, y)
end

function Game:mousepressed(x, y, button)
    -- Right-click clears whatever is armed, wherever it lands.
    if button == 2 then
        self.buildType, self.selected = nil, nil
        return
    end

    if self.hud:mousepressed(x, y, button) then return end
    if button ~= 1 then return end

    local col, row = self.renderer:toGrid(x, y)
    if not col then
        self.selected = nil
        return
    end

    -- A tower already there wins over building: clicking one selects it, which
    -- is the only way to reach its upgrade and sell controls.
    local existing = self.world:towerAt(col, row)
    if existing then
        self.selected = existing
        self.buildType = nil
        UI.Sfx.focus()
    elseif self.buildType then
        self:tryBuild(col, row)
    else
        self.selected = nil
    end
end

--------------------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------------------

function Game:update(dt)
    self.world:update(dt)
    self.renderer:update(dt)
    self.hud:update(dt)

    -- A sold tower must not stay selected, and the panel reads its fields.
    -- Compared by identity rather than by "is something there": selling and
    -- rebuilding on the same tile is a different tower.
    if self.selected and self.world:towerAt(self.selected.col, self.selected.row) ~= self.selected then
        self.selected = nil
    end

    if self.notice then
        self.notice.life = self.notice.life - dt
        if self.notice.life <= 0 then self.notice = nil end
    end

    -- Presence carries the wave number, so it is refreshed when that moves
    -- rather than on a timer.
    if self.world.wave ~= self.presenceWave then self:setPresence() end

    self.sinceSave = self.sinceSave + dt
    if self.sinceSave >= AUTOSAVE_INTERVAL then
        self.sinceSave = 0
        self:save()
    end
end

-- The banner: centered over the top of the board, fading out over its last
-- second so it leaves without the player having to watch it go.
--
-- It carries its own backing panel rather than relying on a drop shadow. This
-- text lands on top of the board, where a tower or a lit path tile directly
-- behind it makes a bare line unreadable — and unlike the pause menu's heading,
-- it appears unannounced, so it has to be legible on the frame it shows up.
function Game:drawNotice()
    local notice = self.notice
    if not notice then return end

    local board = self.renderer.board
    local font = UI.Theme.font("button")
    local alpha = math.min(1, notice.life)
    local padX, padY = UI.Theme.px(18), UI.Theme.px(8)

    local textW = font:getWidth(notice.text)
    local w = math.min(board.w, textW + padX * 2)
    local h = font:getHeight() + padY * 2
    local x = board.x + (board.w - w) / 2
    local y = board.y + UI.Theme.px(12)
    local radius = UI.Theme.metrics.radius

    UI.Theme.setColor(UI.Theme.colors.bg, alpha * 0.92)
    love.graphics.rectangle("fill", x, y, w, h, radius, radius, 8)
    UI.Theme.setColor(notice.color, alpha * 0.55)
    love.graphics.rectangle("line", x, y, w, h, radius, radius, 8)

    UI.Label.draw{
        text = notice.text,
        x = x, y = y + padY, width = w,
        font = font,
        color = notice.color,
        alpha = alpha,
    }
end

function Game:draw()
    self.renderer:draw(self.world, self)
    self.hud:draw()
    self:drawNotice()

    -- Sits just above the bottom bar on the left, where the tower panel (which
    -- is right-aligned) can't reach it. Label.hint's own line would land inside
    -- the build bar.
    local font = UI.Theme.font("small")
    UI.Label.draw{
        text = I18n.t("game.hint"),
        x = self.hud.bar.x,
        y = self.hud.bar.y - UI.Theme.px(6) - font:getHeight(),
        width = self.hud.bar.w,
        font = font,
        color = UI.Theme.colors.textDim,
        align = "left",
        shadow = true,
    }

    -- Asked for every frame the cursor is over something that responds (see
    -- UI.Cursor for why this can't live in mousemoved). The board counts: a
    -- tile you can build on or a tower you can select is as clickable as a
    -- button is.
    if self.mouseX then
        local overBoard = self.hoverCol ~= nil
            and (self.buildType ~= nil or self.world:towerAt(self.hoverCol, self.hoverRow) ~= nil)
        if overBoard or self.hud:hovering(self.mouseX, self.mouseY) then
            UI.Cursor.want("hand")
        end
    end
end

return Game
