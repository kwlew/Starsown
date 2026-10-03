--- The shared surfaces widgets are drawn on: a focusable row and a plain panel.

local Color = require("utils.math").Color
local Colors = require("ui.core.theme.colors")
local Glow = require("ui.core.theme.glow")
local Metrics = require("ui.core.theme.metrics")

local Chrome = {}

local CORNER_TICK = 15 -- design px, how far a row's corner accent reaches along each edge
local CORNER_TICK_REST = 0.3 -- its alpha while the row is unfocused
local CORNER_TICK_SEGMENTS = 6

local TONES = {
    accent = { rest = "panelBorder",  lit = "accent", fill = "accentDark", glow = "glow" },
    danger = { rest = "dangerBorder", lit = "danger", fill = "dangerDark", glow = "danger" },
}

local wedge = {}

--- fills a row's corner out to `leg` along both edges, following the rounded
-- corner rather than cutting across it, so it sits inside the frame
---@param cx number # the corner of the row's bounding box
---@param cy number
---@param dx number # 1 or -1: which way is into the row
---@param dy number
---@param r number # the row's corner radius
---@param leg number
local function cornerWedge(cx, cy, dx, dy, r, leg)
    local n = 0
    local function add(px, py)
        wedge[n + 1], wedge[n + 2] = px, py
        n = n + 2
    end
    add(cx + dx * leg, cy)
    for i = 0, CORNER_TICK_SEGMENTS do
        local a = (math.pi / 2) * i / CORNER_TICK_SEGMENTS
        add(cx + dx * r * (1 - math.sin(a)), cy + dy * r * (1 - math.cos(a)))
    end
    add(cx, cy + dy * leg)
    love.graphics.polygon("fill", unpack(wedge, 1, n))
end

--- the shared look of a focusable row: glow, fill and border, all three
-- interpolated by one 0..1 focus amount
---@param x number
---@param y number
---@param w number
---@param h number
---@param glow number # 0..1 focus amount
---@param time number # seconds, drives the glow's pulse
---@param alpha? number # border alpha, defaults to 1
---@param tone? "accent"|"danger" # defaults to accent
---@param baseGlow? number # 0..1 floor under the fill/border blend only -- lets
-- a row read as tinted/important at rest without the bloom halo also showing;
-- that stays reserved for real focus
---@param fade? number # 0..1 fill and glow opacity, for entrance fades
function Chrome.row(x, y, w, h, glow, time, alpha, tone, baseGlow, fade)
    alpha = alpha or 1
    fade = fade or 1
    local c, m = Colors.colors, Metrics.metrics
    local set = TONES[tone] or TONES.accent
    local lit = c[set.lit]
    local fillGlow = math.max(glow, baseGlow or 0)

    if glow > 0.01 then
        Glow.rect(x, y, w, h, m.radius, glow * Glow.pulse(time) * fade, c[set.glow], true)
    end
    local fr, fg, fb = Color.lerp(c.panel, c[set.fill], fillGlow)
    love.graphics.setColor(fr, fg, fb, fade)
    love.graphics.rectangle("fill", x, y, w, h, m.radius, m.radius, 10)

    -- accents in the top-left and bottom-right corners, lit even at rest and
    -- brighter on focus; drawn before the border so it covers their seam
    local leg = math.max(Metrics.px(CORNER_TICK), m.radius + 2)
    Colors.set(lit, (CORNER_TICK_REST + (1 - CORNER_TICK_REST) * fillGlow) * alpha)
    cornerWedge(x, y, 1, 1, m.radius, leg)
    cornerWedge(x + w, y + h, -1, -1, m.radius, leg)

    local br, bg, bb = Color.lerp(c[set.rest], lit, fillGlow)
    love.graphics.setColor(br, bg, bb, alpha)
    love.graphics.rectangle("line", x, y, w, h, m.radius, m.radius, 10)
end

--- a filled, bordered surface at the theme's corner radius
---@param x number
---@param y number
---@param w number
---@param h number
function Chrome.panel(x, y, w, h)
    local radius = Metrics.metrics.radius
    love.graphics.setColor(Colors.colors.panel)
    love.graphics.rectangle("fill", x, y, w, h, radius, radius, 8)
    love.graphics.setColor(Colors.colors.panelBorder)
    love.graphics.rectangle("line", x, y, w, h, radius, radius, 8)
    love.graphics.setColor(1, 1, 1, 1)
end

return Chrome
