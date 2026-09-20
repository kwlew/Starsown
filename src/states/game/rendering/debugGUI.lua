-- src/states/game/rendering/debugGUI.lua
-- debugging GUI that opens when you press F4.
-- While it is up: left click an entity to damage it, right click to heal it.

local Theme = require "ui.core.theme"
local Math = require "utils.math"
local Perspective = require "states.game.rendering.perspective"
local Globals = require "globals"
local Units = require "states.game.units"
local Palette = require "states.game.rendering.palette"
local Biomes = require "states.game.biomes"

local Overlay = { visible = false, showBiomes = false }
local BIOME_ALPHA = 0.3

local MARGIN = 8
local PAD = 8
local KEY_SIZE = 32
local KEY_GAP = 2
local CLICK_AMOUNT = 1
local PANEL_ALPHA = 0.55

local hovered

--- Toggles the visibility of the overlay.
---@return boolean visible
function Overlay.toggle()
    Overlay.visible = not Overlay.visible
    return Overlay.visible
end

--- Toggles the biome map tint over the world (F5).
---@return boolean shown
function Overlay.toggleBiomes()
    Overlay.showBiomes = not Overlay.showBiomes
    return Overlay.showBiomes
end

--- The topmost entity under a world-space point, if any.
---@param engine table
---@param wx number
---@param wy number
---@return table?
local function entityAt(engine, wx, wy)
    for i = #engine.entities, 1, -1 do
        local e = engine.entities[i]
        local radius = e.radius * Perspective.scale(e.z)
        if Math.length(wx - e.x, wy - e:drawY()) <= radius then return e end
    end
end

---@param engine table
---@param x number # screen
---@param y number # screen
---@param button integer
---@return boolean consumed
function Overlay.mousepressed(engine, x, y, button)
    if not Overlay.visible then return false end
    local target = entityAt(engine, engine:toWorld(x, y))
    if not target then return false end

    if button == 1 then
        target:damage(CLICK_AMOUNT)
    elseif button == 2 then
        target:heal(CLICK_AMOUNT)
    end
    return true
end

--- Ring around whatever the pointer is over. Call inside the camera transform.
---@param engine table
function Overlay.drawWorld(engine)
    if Overlay.showBiomes then
        local left, top, right, bottom = engine:viewRect()
        local c1, r1 = engine.WORLD:toTile(left, top)
        local c2, r2 = engine.WORLD:toTile(right, bottom)
        -- zoomed out, sample one tile per block so the map stays cheap to draw
        local step = math.max(1, math.floor(1 / engine.zoom))
        c1, r1 = c1 - c1 % step, r1 - r1 % step
        for row = r1, r2, step do
            for col = c1, c2, step do
                local biome = assert(Biomes.get(engine.WORLD:biomeAt(col, row)))
                Theme.setColor(Palette.biomes[biome.color], BIOME_ALPHA)
                love.graphics.rectangle("fill", col, row, step, step)
            end
        end
        love.graphics.setColor(1, 1, 1, 1)
    end

    if not Overlay.visible then return end
    hovered = entityAt(engine, engine:toWorld(love.mouse.getPosition()))
    if not hovered then return end

    Theme.setColor(Theme.colors.accent, 0.7)
    love.graphics.circle("line", hovered.x, hovered:drawY(),
        hovered.radius * Perspective.scale(hovered.z) + Units.px(4))
    love.graphics.setColor(1, 1, 1, 1)
end

---@param x number
---@param y number
---@param label string
---@param down boolean
local function drawKey(x, y, label, down)
    if down then
        Theme.setColor(Theme.colors.accent, 0.85)
        love.graphics.rectangle("fill", x, y, KEY_SIZE, KEY_SIZE, 3)
        Theme.setColor(Theme.colors.bg)
    else
        Theme.setColor(Theme.colors.textDim, 0.5)
        love.graphics.rectangle("line", x, y, KEY_SIZE, KEY_SIZE, 3)
        Theme.setColor(Theme.colors.textDim)
    end
    love.graphics.printf(label, x, y + (KEY_SIZE - love.graphics.getFont():getHeight()) / 2, KEY_SIZE, "center")
end

--- Inverted-T key cluster: `top` above, `left/down/right` beneath.
---@param x number
---@param y number
---@param keys string[] # up, extra, left, down, right, then the key left of `up`
---@param labels string[]
local function drawCluster(x, y, keys, labels)
    local step = KEY_SIZE + KEY_GAP
    local function key(i, col, row)
        drawKey(x + col * step, y + row * step, labels[i], love.keyboard.isDown(keys[i]))
    end
    key(6, 0, 0)
    key(1, 1, 0)
    key(2, 2, 0)
    key(3, 0, 1)
    key(4, 1, 1)
    key(5, 2, 1)
end

---@param engine table
---@return string[]
local function infoLines(engine)
    local p = engine.PLAYER
    local col, row = engine.WORLD:toTile(p.x, p.y)
    local facing = math.deg(p.facing) % 360
    local lines = {
        ("pos    %.2f, %.2f m"):format(p.x, p.y),
        ("tile   %d, %d"):format(col, row),
        ("vel    %.1f, %.1f  (%.2f m/s)"):format(p.vx, p.vy, p:speed()),
        ("facing %.0f deg%s"):format(facing, p.aimPinned and "  (at range)" or ""),
        ("stamina %.0f / %.0f"):format(p.stamina, p.maxStamina),
        ("hp     %.0f / %.0f%s"):format(p.hp, p.maxHp, p.dead and "  DEAD" or ""),
        ("stamina %.0f / %.0f%s"):format(p.stamina, p.maxStamina,
            p.exhausted and "  EXHAUSTED" or p.sprinting and "  SPRINT" or ""),
        ("biome  %s  (seed %d)"):format(engine.WORLD:biomeAt(col, row), engine.WORLD.seed),
        ("spawn  %d, %d"):format(engine.spawn.col, engine.spawn.row),
        ("camera %.1f, %.1f m"):format(engine.camX, engine.camY),
        ("entities %d"):format(#engine.entities),
        ("chunks %d  trees %d"):format(engine.CHUNKS:stats()),
    }
    if Globals.dev.enabled then
        lines[#lines + 1] = ("dev    zoom x%.2f   speed x%d"):format(engine.zoom, engine.speedScale)
    end
    if hovered then
        lines[#lines + 1] = ("target hp %.0f / %.0f"):format(hovered.hp, hovered.maxHp)
    end
    return lines
end

--- Screen-space panel, top right. Call outside the camera transform.
---@param engine table
function Overlay.draw(engine)
    if not Overlay.visible then return end

    local font = Theme.font("debug")
    local lineHeight = font:getHeight() + 2
    local lines = infoLines(engine)
    local hint = "click: damage   right click: heal   F5: biome map"
    if Globals.dev.enabled then hint = hint .. "   -/=/0: zoom   [/]: speed" end

    local textWidth = font:getWidth(hint)
    for _, line in ipairs(lines) do textWidth = math.max(textWidth, font:getWidth(line)) end

    local step = KEY_SIZE + KEY_GAP
    local clusterWidth = 3 * step - KEY_GAP
    local clusterHeight = 2 * step - KEY_GAP
    local width = math.max(textWidth, clusterWidth * 2 + PAD) + PAD * 2
    local height = PAD * 2 + #lines * lineHeight + PAD + clusterHeight + PAD + lineHeight

    local x = love.graphics.getWidth() - width - MARGIN
    local y = MARGIN

    Theme.pushFont(font)
    Theme.setColor(Theme.colors.panel, PANEL_ALPHA)
    love.graphics.rectangle("fill", x, y, width, height, 4)

    local cursor = y + PAD
    Theme.setColor(Theme.colors.text)
    for _, line in ipairs(lines) do
        love.graphics.print(line, x + PAD, cursor)
        cursor = cursor + lineHeight
    end

    cursor = cursor + PAD
    drawCluster(x + PAD, cursor, { "w", "e", "a", "s", "d", "c" },
        { "W", "E", "A", "S", "D", "C" })
    drawCluster(x + PAD + clusterWidth + PAD, cursor, { "up", "e", "left", "down", "right", "c" },
        { "^", "E", "<", "v", ">", "C" })

    Theme.setColor(Theme.colors.textDim)
    love.graphics.print(hint, x + PAD, cursor + clusterHeight + PAD)
    Theme.popFont()

    love.graphics.setColor(1, 1, 1, 1)
end

return Overlay
