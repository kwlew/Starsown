--- F3+G, in the world: hitboxes, facing, goals, ranges, tags.

local Math = require("utils.math")
local Swipe = require("game.swipe")
local Tile = require("game.tile")
local UI = require("ui")

local WorldOverlay = {}

local VELOCITY_SCALE = 0.25 -- seconds of travel the line shows
local FACING_LENGTH = 12
local ARROW = 5
local TAG_GAP = 4
local TAG_W = 240
local LINE_W = 1.5

local function arrow(x, y, angle, length)
    local tx, ty = Math.polar(x, y, angle, length)
    local head = UI.Theme.px(ARROW)
    love.graphics.line(x, y, tx, ty)
    love.graphics.line(tx, ty, Math.polar(tx, ty, angle + math.pi * 0.8, head))
    love.graphics.line(tx, ty, Math.polar(tx, ty, angle - math.pi * 0.8, head))
end

---@param e table
---@return string
local function tag(e)
    local parts = { e.name }
    if e.maxHealth > 1 then parts[#parts + 1] = ("%d/%d"):format(math.ceil(e.health), e.maxHealth) end
    if e.kind == "player" then
        local stamina = e.stamina
        parts[#parts + 1] = stamina.exhausted and "exhausted" or ("stamina %d"):format(stamina.value)
    elseif e.state then
        parts[#parts + 1] = e.state
    end
    if e.invulnerable > 0 then parts[#parts + 1] = ("inv %.1fs"):format(e.invulnerable) end
    return table.concat(parts, "  ")
end

--- aggro, reach, throw band and windup for hostiles
local function hostileRanges(e, x, y, s)
    local Theme, c = UI.Theme, UI.Theme.colors
    local target = e.target and e.target:isValid() and e.target
    Theme.setColor(c.danger, target and 0.3 or 0.1)
    love.graphics.circle("line", x, y, e.aggroRange * s, 48)
    Theme.setColor(c.danger, 0.3)
    love.graphics.circle("line", x, y, (e.radius + e.attackReach) * s, 24)
    if target then
        Theme.setColor(c.danger, 0.7)
        love.graphics.line(x, y, target.x * s, target.y * s)
        if e.throwRange then
            Theme.setColor(c.warning, 0.2)
            love.graphics.circle("line", x, y, e.throwMinRange * s, 40)
            love.graphics.circle("line", x, y, e.throwRange * s, 48)
        end
    end
    if e.windup and e.throwWindup then
        Theme.setColor(c.warning, 0.9)
        local done = 1 - e.windup / e.throwWindup
        love.graphics.arc("line", "open", x, y, (e.radius + 4) * s, -math.pi / 2, -math.pi / 2 + done * math.pi * 2, 24)
    end
end

--- sword reach and aim for the player
local function playerRanges(e, x, y, s)
    local Theme, c = UI.Theme, UI.Theme.colors
    Theme.setColor(c.highlight, 0.3)
    love.graphics.circle("line", x, y, Swipe.REACH * s, 32)
    if e.aimX then
        Theme.setColor(c.highlight, 0.5)
        love.graphics.line(x, y, e.aimX * s, e.aimY * s)
        love.graphics.circle("line", e.aimX * s, e.aimY * s, Theme.px(4), 12)
    end
end

local function drawEntity(e, alpha, s, font)
    local Theme = UI.Theme
    local ex, ey = e:lerpPosition(alpha)
    local x, y = ex * s, ey * s
    local color = e:color()

    if e.aggroRange then hostileRanges(e, x, y, s) end
    if e.swipe then playerRanges(e, x, y, s) end
    if e.goalX then
        Theme.setColor(color, 0.5)
        love.graphics.line(x, y, e.goalX * s, e.goalY * s)
        Theme.setColor(color, 0.9)
        love.graphics.circle("line", e.goalX * s, e.goalY * s, Theme.px(5), 16)
    end

    Theme.setColor(color, 0.9)
    love.graphics.circle("line", x, y, e.radius * s, 24)
    arrow(x, y, e:drawAngle(ex, ey, alpha), (e.radius + FACING_LENGTH) * s)
    if e.vx ~= 0 or e.vy ~= 0 then
        Theme.setColor(Theme.colors.text, 0.6)
        love.graphics.line(x, y, x + e.vx * VELOCITY_SCALE * s, y + e.vy * VELOCITY_SCALE * s)
    end

    local width = Theme.px(TAG_W)
    UI.Label.draw{ text = tag(e), x = Math.round(x - width / 2),
        y = Math.round(y - e.radius * s - Theme.px(TAG_GAP) - font:getHeight()),
        width = width, font = font, shadow = true }
end

--- inside the camera, after the world
---@param world table
---@param alpha number
function WorldOverlay.draw(world, alpha)
    local s, font = Tile.worldScale(), UI.Theme.font("small")
    love.graphics.push("all")
    love.graphics.setLineWidth(math.max(1, UI.Theme.px(LINE_W)))
    for e in world:each() do drawEntity(e, alpha, s, font) end
    love.graphics.pop()
end

return WorldOverlay
