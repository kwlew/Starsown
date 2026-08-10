-- src/game/renderer.lua
-- Draws the board and everything standing on it, and owns the one conversion
-- between grid space and the screen. The world knows nothing about pixels; this
-- is the only file that turns a tile into a rectangle.
--
--   renderer:layout(x, y, w, h)   -- fit the board into this area
--   renderer:toScreen(gx, gy)     -- grid point -> pixels
--   renderer:toGrid(px, py)       -- pixels -> col, row (nil off-board)
--   renderer:draw(world, view)
--
-- `view` is the UI's transient state, passed in rather than stored, so the
-- renderer stays a pure function of (world, view) and holds nothing that could
-- go stale: { hoverCol, hoverRow, buildType, selected }.
--
-- Sizes on the board are expressed as fractions of a tile, not through
-- Theme.px: the board already scales itself to the window, and scaling its
-- contents a second time by the UI scale would make towers drift out of their
-- tiles at other resolutions. Theme.px is still right for anything measured in
-- screen furniture (the floating text, line widths).

local Theme = require "ui.theme"
local Glyph = require "ui.glyph"
local Map = require "game.map"
local Config = require "game.config"

local Renderer = {}
Renderer.__index = Renderer

-- All as fractions of one tile.
local TOWER_INSET   = 0.12 -- gap between a tower and its tile edge
local TOWER_ICON    = 0.52
local BARREL_LENGTH = 0.44
local PIP_RADIUS    = 0.045 -- the level dots under a tower
local PROJECTILE    = 0.09
local HEALTH_BAR_W  = 0.58 -- about an enemy's own width, so it reads as *its* bar
local HEALTH_BAR_H  = 0.085
local PATH_CENTER   = 0.10 -- width of the direction line down the path

-- Floating text (a bounty, a warning) rises this many tiles over its lifetime.
local FLOAT_RISE = 0.9
local FLOAT_LIFE = 1.1

function Renderer.new()
    return setmetatable({
        tile = 1,
        originX = 0, originY = 0,
        board = { x = 0, y = 0, w = 0, h = 0 },
        floaters = {},
        time = 0,
    }, Renderer)
end

--------------------------------------------------------------------------------
-- Geometry
--------------------------------------------------------------------------------

-- Fits the whole board inside the given area and centers it. The tile size is
-- floored to a whole pixel so the grid lines land on pixel boundaries instead of
-- shimmering between them.
function Renderer:layout(x, y, w, h)
    local tile = math.floor(math.min(w / Map.COLS, h / Map.ROWS))
    self.tile = math.max(1, tile)

    local boardW, boardH = self.tile * Map.COLS, self.tile * Map.ROWS
    self.board.x = math.floor(x + (w - boardW) / 2)
    self.board.y = math.floor(y + (h - boardH) / 2)
    self.board.w, self.board.h = boardW, boardH

    -- Grid point (1, 1) is the CENTER of the top-left tile, so the origin sits
    -- half a tile back from the board's corner.
    self.originX = self.board.x - self.tile * 0.5
    self.originY = self.board.y - self.tile * 0.5
end

function Renderer:toScreen(gx, gy)
    return self.originX + gx * self.tile, self.originY + gy * self.tile
end

-- The tile under a screen point, or nil when the point is off the board.
function Renderer:toGrid(px, py)
    local col = math.floor((px - self.board.x) / self.tile) + 1
    local row = math.floor((py - self.board.y) / self.tile) + 1
    if not Map.inBounds(col, row) then return nil end
    return col, row
end

function Renderer:contains(px, py)
    local b = self.board
    return Theme.pointIn(px, py, b.x, b.y, b.w, b.h)
end

--------------------------------------------------------------------------------
-- Floating text
--------------------------------------------------------------------------------

-- Spawned by the game state from the world's events. Purely cosmetic and held
-- here rather than in the world, so the simulation stays free of anything that
-- exists only to be looked at.
function Renderer:floater(gx, gy, text, color)
    self.floaters[#self.floaters + 1] = {
        x = gx, y = gy, text = text, color = color, life = FLOAT_LIFE,
    }
end

function Renderer:update(dt)
    self.time = self.time + dt

    local kept = 0
    for i = 1, #self.floaters do
        local f = self.floaters[i]
        f.life = f.life - dt
        if f.life > 0 then
            kept = kept + 1
            self.floaters[kept] = f
        end
    end
    for i = #self.floaters, kept + 1, -1 do
        self.floaters[i] = nil
    end
end

--------------------------------------------------------------------------------
-- The board
--------------------------------------------------------------------------------

function Renderer:drawBoard()
    local c = Theme.colors
    local b = self.board
    local radius = Theme.metrics.radius

    love.graphics.setColor(c.panel)
    love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, radius, radius, 8)

    -- Grid: faint, and only there to make distances readable when placing a
    -- tower. Anything more assertive competes with the path.
    love.graphics.setLineWidth(1)
    Theme.setColor(c.panelBorder, 0.22)
    for col = 1, Map.COLS - 1 do
        local x = b.x + col * self.tile
        love.graphics.line(x, b.y, x, b.y + b.h)
    end
    for row = 1, Map.ROWS - 1 do
        local y = b.y + row * self.tile
        love.graphics.line(b.x, y, b.x + b.w, y)
    end

    -- The route, as filled tiles. Blocky rather than a smooth ribbon because
    -- the rule the player needs to read is "which tiles can I build on", and a
    -- tile is the unit that answers it.
    Theme.setColor(c.track)
    for row = 1, Map.ROWS do
        for col = 1, Map.COLS do
            if Map.isPath(col, row) then
                love.graphics.rectangle("fill",
                    b.x + (col - 1) * self.tile, b.y + (row - 1) * self.tile,
                    self.tile, self.tile)
            end
        end
    end

    love.graphics.setColor(c.panelBorder)
    love.graphics.rectangle("line", b.x, b.y, b.w, b.h, radius, radius, 8)
end

-- A dim line down the middle of the route. Reads as direction of travel, and
-- keeps the path from looking like a corridor of empty tiles.
function Renderer:drawPathCenter()
    local outline = Map.outline()
    local points = {}
    for i = 1, #outline, 2 do
        local x, y = self:toScreen(outline[i], outline[i + 1])
        points[#points + 1] = x
        points[#points + 1] = y
    end

    love.graphics.setLineWidth(math.max(1, self.tile * PATH_CENTER))
    Theme.setColor(Theme.colors.accent, 0.28)
    love.graphics.line(points)
    love.graphics.setLineWidth(1)
end

--------------------------------------------------------------------------------
-- Towers
--------------------------------------------------------------------------------

function Renderer:drawRangeCircle(col, row, range, color, alpha)
    local x, y = self:toScreen(col, row)
    local radius = range * self.tile

    Theme.setColor(color, (alpha or 1) * 0.10)
    love.graphics.circle("fill", x, y, radius)
    love.graphics.setLineWidth(math.max(1, Theme.px(1)))
    Theme.setColor(color, (alpha or 1) * 0.55)
    love.graphics.circle("line", x, y, radius)
    love.graphics.setLineWidth(1)
end

function Renderer:drawTower(tower, selected)
    local c = Theme.colors
    local def = Config.towerById[tower.type]
    local inset = self.tile * TOWER_INSET
    local x = self.board.x + (tower.col - 1) * self.tile + inset
    local y = self.board.y + (tower.row - 1) * self.tile + inset
    local size = self.tile - inset * 2
    local radius = size * 0.22
    local cx, cy = x + size / 2, y + size / 2

    if selected then
        Theme.glowRect(x, y, size, size, radius, Theme.pulse(self.time))
    end

    love.graphics.setColor(c.accentDark)
    love.graphics.rectangle("fill", x, y, size, size, radius, radius, 6)
    Theme.setColor(c.accent, selected and 1 or 0.7)
    love.graphics.setLineWidth(math.max(1, Theme.px(1)))
    love.graphics.rectangle("line", x, y, size, size, radius, radius, 6)

    -- The barrel: the one part that moves, so the board reads as alive even
    -- when nothing is being hit.
    love.graphics.setLineWidth(math.max(1, self.tile * 0.09))
    Theme.setColor(c.accent, 0.9)
    love.graphics.line(cx, cy,
        cx + math.cos(tower.angle) * self.tile * BARREL_LENGTH,
        cy + math.sin(tower.angle) * self.tile * BARREL_LENGTH)
    love.graphics.setLineWidth(1)

    local icon = self.tile * TOWER_ICON
    Theme.setColor(c.text)
    Glyph.draw(def.icon, cx - icon / 2, cy - icon / 2, icon)

    -- Level, as pips along the bottom edge. A number would need a font sized to
    -- the tile; dots read at a glance and cost nothing to scale.
    if tower.level > 1 then
        local pip = self.tile * PIP_RADIUS
        local gap = pip * 2.6
        local startX = cx - gap * (tower.level - 1) / 2
        Theme.setColor(c.warning)
        for i = 1, tower.level do
            love.graphics.circle("fill", startX + gap * (i - 1), y + size - pip * 1.6, pip)
        end
    end
end

--------------------------------------------------------------------------------
-- Enemies and shots
--------------------------------------------------------------------------------

function Renderer:drawEnemy(enemy)
    local c = Theme.colors
    local x, y = self:toScreen(enemy.x, enemy.y)
    local radius = enemy.size * self.tile

    local body = enemy.boss and c.warning or c.danger
    if enemy.boss then
        Theme.setColor(body, 0.35)
        love.graphics.circle("fill", x, y, radius * 1.5)
    end

    love.graphics.setColor(body)
    love.graphics.circle("fill", x, y, radius)

    -- Slowed enemies wear a ring in the frost tower's own accent, so the effect
    -- is visible on the enemy rather than only in the tower's stats.
    if enemy.slowFor > 0 then
        Theme.setColor(c.accentAlt, 0.9)
        love.graphics.setLineWidth(math.max(1, self.tile * 0.06))
        love.graphics.circle("line", x, y, radius * 1.35)
        love.graphics.setLineWidth(1)
    end

    -- Only once it has been hit: a full bar over every enemy on screen is
    -- noise, and "undamaged" is already what no bar means.
    if enemy.health < enemy.maxHealth then
        local w = self.tile * HEALTH_BAR_W
        local h = math.max(2, self.tile * HEALTH_BAR_H)
        local bx, by = x - w / 2, y - radius - h * 1.6
        local ratio = math.max(0, enemy.health / enemy.maxHealth)

        -- The empty part of the track has to be visible, or a nearly-full bar
        -- is just a bright dash floating over the board with nothing to read it
        -- against. Track first, then the fill, then a hairline to bound it.
        Theme.setColor(c.bg, 0.85)
        love.graphics.rectangle("fill", bx, by, w, h, h / 2, h / 2)
        -- White draining to red, rather than the accent: a health bar has to
        -- mean the same thing in every palette, and Carbon's accent is nearly
        -- the colour of the track behind it.
        Theme.setColor(ratio > 0.35 and c.text or c.danger)
        love.graphics.rectangle("fill", bx, by, w * ratio, h, h / 2, h / 2)
        love.graphics.setLineWidth(1)
        Theme.setColor(c.panelBorder, 0.7)
        love.graphics.rectangle("line", bx, by, w, h, h / 2, h / 2)
    end
end

function Renderer:drawProjectile(projectile)
    local x, y = self:toScreen(projectile.x, projectile.y)
    local radius = math.max(1, self.tile * PROJECTILE)

    -- Splash shots carry a halo so a cannon shell reads as heavier than a
    -- bullet without needing a second sprite.
    if projectile.targets > 1 then
        Theme.setColor(Theme.colors.warning, 0.30)
        love.graphics.circle("fill", x, y, radius * 2.2)
        Theme.setColor(Theme.colors.warning)
    else
        Theme.setColor(Theme.colors.text)
    end
    love.graphics.circle("fill", x, y, radius)
end

--------------------------------------------------------------------------------
-- Overlays
--------------------------------------------------------------------------------

-- The ghost under the cursor while a tower type is selected: where it would go,
-- what it would cover, and whether it can go there at all.
function Renderer:drawBuildPreview(world, view)
    local col, row = view.hoverCol, view.hoverRow
    if not col or not view.buildType then return end

    local def = Config.towerById[view.buildType]
    if not def then return end

    local ok = world:canBuild(col, row, view.buildType)
    local color = ok and Theme.colors.accent or Theme.colors.danger

    self:drawRangeCircle(col, row, def.range, color, ok and 1 or 0.8)

    local inset = self.tile * TOWER_INSET
    local x = self.board.x + (col - 1) * self.tile + inset
    local y = self.board.y + (row - 1) * self.tile + inset
    local size = self.tile - inset * 2
    local radius = size * 0.22

    Theme.setColor(color, 0.18)
    love.graphics.rectangle("fill", x, y, size, size, radius, radius, 6)
    Theme.setColor(color, 0.85)
    love.graphics.setLineWidth(math.max(1, Theme.px(1)))
    love.graphics.rectangle("line", x, y, size, size, radius, radius, 6)
    love.graphics.setLineWidth(1)

    local icon = self.tile * TOWER_ICON
    Theme.setColor(color, 0.85)
    Glyph.draw(def.icon, x + (size - icon) / 2, y + (size - icon) / 2, icon)
end

function Renderer:drawFloaters()
    local font = Theme.font("small")
    Theme.pushFont(font)

    local b = self.board
    local width = self.tile * 4

    for _, f in ipairs(self.floaters) do
        local t = 1 - f.life / FLOAT_LIFE
        local x, y = self:toScreen(f.x, f.y - t * FLOAT_RISE)
        -- Fades over the back half only, so the number is fully legible for
        -- long enough to be read before it starts going.
        local alpha = math.min(1, f.life / (FLOAT_LIFE * 0.5))

        -- Kept inside the board. Everything here is drawn under the board's
        -- scissor so enemies can walk in from off-map, but a bounty popping off
        -- an enemy killed near the edge would be sliced down the middle of a
        -- digit — which reads as a glitch rather than as a number leaving.
        local left = math.max(b.x, math.min(x - width / 2, b.x + b.w - width))

        Theme.setColor(Theme.colors.shadow, alpha * 0.8)
        love.graphics.printf(f.text, left + 1, y + 1, width, "center")
        Theme.setColor(f.color or Theme.colors.text, alpha)
        love.graphics.printf(f.text, left, y, width, "center")
    end

    Theme.popFont()
end

--------------------------------------------------------------------------------

function Renderer:draw(world, view)
    self:drawBoard()
    self:drawPathCenter()

    -- Everything that moves is clipped to the board, so enemies walking in from
    -- off-map appear at the edge instead of sliding across the HUD.
    local b = self.board
    love.graphics.setScissor(b.x, b.y, b.w, b.h)

    -- A selected tower shows its reach; otherwise the hovered one does, so the
    -- board answers "what does this cover" without a click.
    local ranged = view.selected or (view.hoverCol and world:towerAt(view.hoverCol, view.hoverRow))
    if ranged and not view.buildType then
        self:drawRangeCircle(ranged.col, ranged.row, ranged.range, Theme.colors.accent, 0.9)
    end

    self:drawBuildPreview(world, view)

    for _, tower in ipairs(world.towers) do
        self:drawTower(tower, tower == view.selected)
    end
    for _, enemy in ipairs(world.enemies) do
        self:drawEnemy(enemy)
    end
    for _, projectile in ipairs(world.projectiles) do
        self:drawProjectile(projectile)
    end

    self:drawFloaters()

    love.graphics.setScissor()
    love.graphics.setColor(1, 1, 1, 1)
end

return Renderer
