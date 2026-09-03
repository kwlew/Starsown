--- F4 overlay for the play screen: where you are on the grid, where the cursor
-- is, and which inputs are down right now. core/debug.lua's F3 panel is the
-- engine-level one (fps, memory) and knows nothing about a world, so this is a
-- separate module in the opposite corner and the two can be read at once.

local Theme = require "ui.core.theme"
local World = require "game.world"
local Swipe = require "game.swipe"

local Overlay = { visible = false }

local PAD = 8
local PANEL_W = 208
local LINE_GAP = 2
local COLUMN = 74 -- design px reserved for the row's name before its value
local PANEL_ALPHA = 0.88

local CHIP = 22
local CHIP_GAP = 4
local CHIP_RADIUS = 4

local LABEL_RADIUS = 3
local LABEL_FIT = 0.88 -- of the tile's width, so a two-part label stays inside its own square

local ACTION_KEY = { up = "W", left = "A", down = "S", right = "D" }
local BOTTOM_ROW = { "left", "down", "right" }

---@return boolean visible
function Overlay.toggle()
    Overlay.visible = not Overlay.visible
    return Overlay.visible
end

---@param world table
---@param col integer
---@param row integer
---@param color number[]
---@param alpha? number
local function outlineTile(world, col, row, color, alpha)
    local x, y = world:tileOrigin(col, row)
    Theme.setColor(color, alpha or 1)
    love.graphics.rectangle("line", x, y, World.TILE, World.TILE)
end

--- drawn inside the camera transform: 1/zoom brings the glyphs back to the size
-- they were rasterized at, and the fit factor shrinks a wide label the rest of
-- the way so it stays inside the square it names
---@param world table
---@param col integer
---@param row integer
---@param font any # a love.Font
---@param zoom number # the camera's, to undo
---@param alpha number
local function tileLabel(world, col, row, font, zoom, alpha)
    local text = col .. "," .. row
    local width = font:getWidth(text)
    local scale = math.min(1 / zoom, World.TILE * LABEL_FIT / width)
    local x, y = world:tileOrigin(col, row)

    Theme.setColor(Theme.colors.textDim, alpha)
    love.graphics.print(text,
        x + (World.TILE - width * scale) / 2,
        y + (World.TILE - font:getHeight() * scale) / 2,
        0, scale, scale)
end

--- the in-world half: tile coordinates around the player, the player's and
-- aim's own tiles outlined, and the swipe's reach. Call inside the camera
-- transform.
---@param ctx table # reads ctx.world, ctx.camera and ctx.player
function Overlay.drawWorld(ctx)
    local world, camera, player = ctx.world, ctx.camera, ctx.player
    local colors = Theme.colors
    local font = Theme.font("debug")

    local playerCol, playerRow = world:toTile(player.x, player.y)
    local mouseCol, mouseRow = world:toTile(player.aimX, player.aimY)

    Theme.pushFont(font)
    for row = playerRow - LABEL_RADIUS, playerRow + LABEL_RADIUS do
        for col = playerCol - LABEL_RADIUS, playerCol + LABEL_RADIUS do
            tileLabel(world, col, row, font, camera.zoom, 0.45)
        end
    end
    if mouseCol ~= playerCol or mouseRow ~= playerRow then
        tileLabel(world, mouseCol, mouseRow, font, camera.zoom, 0.9)
    end
    Theme.popFont()

    love.graphics.setLineWidth(2)
    outlineTile(world, mouseCol, mouseRow, colors.warning, 0.9)
    outlineTile(world, playerCol, playerRow, colors.accent, 0.9)

    Theme.setColor(colors.accent, 0.25)
    love.graphics.arc("line", "open", player.x, player.y, Swipe.REACH,
        player.facing - Swipe.ARC / 2, player.facing + Swipe.ARC / 2)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

---@param x number
---@param y number
---@param w number
---@param h number
---@param label string
---@param held boolean # lights it up
---@param font any # a love.Font
local function chip(x, y, w, h, label, held, font)
    local colors = Theme.colors
    Theme.setColor(held and colors.accentDark or colors.panel, 0.9)
    love.graphics.rectangle("fill", x, y, w, h, CHIP_RADIUS)
    Theme.setColor(held and colors.accent or colors.panelBorder)
    love.graphics.rectangle("line", x, y, w, h, CHIP_RADIUS)

    Theme.setColor(held and colors.text or colors.textDim)
    love.graphics.print(label,
        x + (w - font:getWidth(label)) / 2,
        y + (h - font:getHeight()) / 2)
end

--- the WASD cross with the mouse button under it, lit for whatever is down
---@param ctx table # reads ctx.player
---@param x number # top-left of the cross
---@param y number
---@param font any # a love.Font
local function drawInputs(ctx, x, y, font)
    local size = Theme.px(CHIP)
    local step = size + Theme.px(CHIP_GAP)
    local held = ctx.player.held

    chip(x + step, y, size, size, ACTION_KEY.up, held.up, font)
    for index, action in ipairs(BOTTOM_ROW) do
        chip(x + (index - 1) * step, y + step, size, size,
            ACTION_KEY[action], held[action], font)
    end
    chip(x, y + step * 2, step * 3 - Theme.px(CHIP_GAP), size,
        "LMB", ctx.player.attacking, font)
end

--- the readout panel, top right, in screen space -- opposite corner from
-- core/debug.lua's F3 panel so both can be up at once
---@param ctx table # reads ctx.world, ctx.player, ctx.enemies and ctx.pauseState
function Overlay.drawScreen(ctx)
    local world, player = ctx.world, ctx.player
    local colors = Theme.colors
    local font = Theme.font("debug")
    local pad = Theme.px(PAD)
    local width = Theme.px(PANEL_W)
    local column = Theme.px(COLUMN)
    local lineHeight = font:getHeight() + Theme.px(LINE_GAP)

    local playerCol, playerRow = world:toTile(player.x, player.y)
    local mouseCol, mouseRow = world:toTile(player.aimX, player.aimY)

    local rows = {
        { "pos", ("%.1f, %.1f"):format(player.x, player.y) },
        { "tile", playerCol .. ", " .. playerRow },
        { "aim", ("%.0f, %.0f"):format(player.aimX, player.aimY) },
        { "aim tile", mouseCol .. ", " .. mouseRow },
        { "range", player.RANGE .. (player.aimPinned and " pinned" or " free") },
        { "facing", ("%.0f deg"):format(math.deg(player.facing) % 360) },
        { "speed", ("%.0f"):format(player:speed()) },
        { "height", ("%.1f"):format(player.z) },
        { "swipe", player.swipe:ready() and "ready" or ("%.2fs"):format(player.swipe.cooldown) },
        { "hp", ("%d / %d"):format(player.hp, player.maxHp) },
        { "enemies", tostring(#ctx.enemies) },
        { "state", ctx.pauseState or "running" },
        { "ground", World.TILE .. "px " .. (world.texture and "textured" or "flat") },
    }

    local gap = pad / 2 -- between the readout and the input chips
    local chipsHeight = Theme.px(CHIP) * 3 + Theme.px(CHIP_GAP) * 2
    local height = pad * 2 + lineHeight * #rows + gap + chipsHeight
    local x = love.graphics.getWidth() - width - pad
    local y = pad

    Theme.setColor(colors.bg, PANEL_ALPHA)
    love.graphics.rectangle("fill", x, y, width, height, Theme.metrics.radius)
    Theme.setColor(colors.panelBorder, 0.8)
    love.graphics.rectangle("line", x, y, width, height, Theme.metrics.radius)

    Theme.pushFont(font)
    local textY = y + pad
    for _, row in ipairs(rows) do
        Theme.setColor(colors.textDim)
        love.graphics.print(row[1], x + pad, textY)
        Theme.setColor(colors.text)
        love.graphics.print(row[2], x + pad + column, textY)
        textY = textY + lineHeight
    end

    drawInputs(ctx, x + pad, textY + gap, font)
    Theme.popFont()

    love.graphics.setColor(1, 1, 1, 1)
end

return Overlay
