-- lib/ui/theme.lua
-- The style contract for the whole game: every color, font, and metric the UI
-- uses lives here, so changing the game's look means editing this file only.
-- Widgets and states must never hardcode style values — ask the theme.
--
-- Everything sized in pixels is expressed at a 720p design height and scaled by
-- Theme.scale (see Theme.rescale), so the UI keeps its proportions from 768p up
-- to 1080p instead of shrinking into the middle of a big screen.

local Math = require "lib.utils.math"

local Theme = {}

-- Where the UI font family lives. Each role below picks its own weight from it:
-- a single weight for every role is what makes dense screens read as noise, so
-- headings/buttons get the heavy cuts and body/hint text gets the light ones.
local FONT_DIR = "assets/fonts/Oxanium/"

Theme.colors = {
    bg          = { 0.05, 0.05, 0.07 }, -- window clear color
    panel       = { 0.10, 0.11, 0.14 }, -- widget/panel background
    panelBorder = { 0.25, 0.28, 0.35 },
    track       = { 0.18, 0.18, 0.20 }, -- empty bar/slider track
    text        = { 0.92, 0.94, 0.98 },
    textMuted   = { 0.72, 0.75, 0.82 }, -- secondary text that still reads as text
    textDim     = { 0.55, 0.58, 0.65 }, -- hints, footers, debug overlay
    accent      = { 0.30, 0.70, 1.00 }, -- the neon blue: focus, fills, glow
    accentDark  = { 0.13, 0.30, 0.45 }, -- focused-widget background
    accentAlt   = { 0.62, 0.40, 1.00 }, -- violet partner for gradients
    warning     = { 1.00, 0.75, 0.25 },
    danger      = { 0.95, 0.35, 0.35 },
}

-- Design-space metrics, in px at Theme.scale == 1. Theme.metrics holds these
-- multiplied by the live scale; read that, never this.
local baseMetrics = {
    radius     = 8,  -- corner radius for every rounded rect
    padding    = 14, -- inner padding of widgets/panels
    rowHeight  = 48, -- standard widget row height
    rowGap     = 14, -- vertical gap between stacked widgets
    glowSpread = 4,  -- px each glow layer grows beyond the last
}

-- Unitless metrics: counts, alphas, and rates, which must NOT scale with
-- resolution (a glow that gets more opaque on a bigger monitor is a bug).
local constantMetrics = {
    glowLayers = 4,  -- additive rects stacked into a halo
    glowAlpha  = 0.16,
    focusSpeed = 10, -- how fast widgets ease toward their focused look
}

-- Point sizes at scale 1, plus the weight each role is cut from. Sizes alone
-- can't build a hierarchy — weight is what separates a heading from the body
-- text sitting right under it.
local fontRoles = {
    title   = { file = "Oxanium-ExtraBold.ttf", size = 72 }, -- game title
    heading = { file = "Oxanium-Bold.ttf",      size = 40 }, -- screen headings
    button  = { file = "Oxanium-SemiBold.ttf",  size = 26 }, -- buttons, tabs
    body    = { file = "Oxanium-Medium.ttf",    size = 26 }, -- widget labels/values
    small   = { file = "Oxanium-Regular.ttf",   size = 15 }, -- hints, readouts
    debug   = { file = "Oxanium-Medium.ttf",    size = 14 }, -- dev overlay
}

Theme.metrics = {}
Theme.scale = 0 -- 0 until the first rescale, so it can never match a real scale

local DESIGN_HEIGHT = 720
-- Clamped so a very short window doesn't render unreadably small and a tall one
-- doesn't blow the UI up past the point where a panel still fits; quantized so
-- font sizes land on stable integers instead of resampling by a pixel.
local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.85, 1.6, 0.05

local fontCache = {}

local function scaleForHeight(height)
    local s = Math.clamp(height / DESIGN_HEIGHT, SCALE_MIN, SCALE_MAX)
    return Math.round(s / SCALE_STEP) * SCALE_STEP
end

-- Recomputes the scale from the window height, rebuilding metrics and dropping
-- the font cache so the next Theme.font call rebuilds at the new size. Returns
-- true when the scale actually changed, so callers can skip relayout work.
--
-- Call from love.load and love.resize. Fonts are resolved per draw (see
-- Theme.fontFor), so widgets built before a rescale pick the new sizes up on
-- their own — but anything that cached a Font or a love.graphics.newText mesh
-- itself (TextFactory) has to rebuild when this returns true.
function Theme.rescale(height)
    local s = scaleForHeight(height or love.graphics.getHeight())
    if s == Theme.scale then return false end
    Theme.scale = s

    -- Mutated in place: widgets and states hold references to this table.
    for key, value in pairs(baseMetrics) do
        Theme.metrics[key] = Math.round(value * s)
    end
    for key, value in pairs(constantMetrics) do
        Theme.metrics[key] = value
    end

    fontCache = {}
    return true
end

-- Scales a caller's own design-space pixel constant (a widget's track height, a
-- screen's panel padding). Use for any literal px value outside Theme.metrics.
function Theme.px(value)
    return Math.round(value * Theme.scale)
end

function Theme.font(name)
    local role = fontRoles[name]
    assert(role, "Theme.font: unknown font '" .. tostring(name) .. "'")
    if not fontCache[name] then
        local size = math.max(1, Math.round(role.size * Theme.scale))
        -- Fall back to LÖVE's default font if the .ttf can't be opened, so a
        -- missing/renamed font file degrades gracefully instead of crashing
        -- (also lets headless tests run without the assets dir mounted).
        local ok, font = pcall(love.graphics.newFont, FONT_DIR .. role.file, size)
        fontCache[name] = ok and font or love.graphics.newFont(size)
    end
    return fontCache[name]
end

-- Every role name, so the loading screen can warm the whole cache in one pass
-- instead of naming each role and drifting out of sync with this file.
function Theme.fontRoles()
    local names = {}
    for name in pairs(fontRoles) do names[#names + 1] = name end
    table.sort(names)
    return names
end

-- Resolves a widget's configured font. Widgets store whatever was passed to
-- them and call this at draw time rather than resolving in their constructor:
-- a Font object captured at construction survives a Theme.rescale and leaves
-- that one widget rendering at the old resolution's size forever.
--
--   font = nil       -> the widget's default role
--   font = "heading" -> that role, resolved fresh each draw (scale-aware)
--   font = <Font>    -> that exact font, caller owns keeping it in scale
function Theme.fontFor(font, defaultRole)
    if type(font) == "userdata" then return font end
    return Theme.font(type(font) == "string" and font or defaultRole)
end

-- setColor for a theme color table, with an optional alpha override. Replaces
-- the c[1], c[2], c[3], alpha splat every widget was writing out by hand.
function Theme.setColor(color, alpha)
    love.graphics.setColor(color[1], color[2], color[3], alpha or color[4] or 1)
end

-- Component-wise lerp between two colors; returns r, g, b for setColor.
function Theme.lerp(a, b, t)
    return a[1] + (b[1] - a[1]) * t,
           a[2] + (b[2] - a[2]) * t,
           a[3] + (b[3] - a[3]) * t
end

function Theme.pointIn(px, py, x, y, w, h)
    return px >= x and px <= x + w and py >= y and py <= y + h
end

-- Frame-rate-independent eased step of `current` toward `target` (the widgets'
-- shared glow/knob/highlight animation). `speed` defaults to the shared focus
-- rate; pass one for a follower that needs its own pace.
function Theme.approach(current, target, dt, speed)
    return current + (target - current) * math.min(dt * (speed or Theme.metrics.focusSpeed), 1)
end

-- The shared 0.5..1 breathing pulse used by every focused glow, driven by a
-- widget's accumulated `time`.
function Theme.pulse(time)
    return 0.75 + 0.25 * math.sin(time * 3)
end

-- The y at which a line of `font` is vertically centered in a row of height h
-- starting at y. Every widget uses this to place its label.
function Theme.centerY(y, h, font)
    return y + (h - font:getHeight()) / 2
end

-- Font stack, so a widget draw doesn't repeat the getFont/setFont/restore
-- dance. Deliberately not a callback form: that allocates a fresh closure per
-- widget per frame purely to scope two lines of drawing.
--
--   Theme.pushFont(font)
--   ...draw...
--   Theme.popFont()
local fontStack = {}

function Theme.pushFont(font)
    fontStack[#fontStack + 1] = love.graphics.getFont()
    love.graphics.setFont(font)
end

function Theme.popFont()
    local depth = #fontStack
    assert(depth > 0, "Theme.popFont: no matching pushFont")
    love.graphics.setFont(fontStack[depth])
    fontStack[depth] = nil
end

-- Resolves a widget label that may be a plain string or a function(owner) ->
-- string. Function labels are what let localized text update live: a label of
-- function() return I18n.t("menu.play") end re-reads the active language every
-- draw, so switching language needs no rebuild.
function Theme.resolveLabel(label, owner)
    if type(label) == "function" then
        return label(owner)
    end
    return label or ""
end

-- Soft additive halo around a rounded rect (the loading bar's glow,
-- generalized). intensity scales brightness; color defaults to accent.
-- Restores alpha blending before returning.
function Theme.glowRect(x, y, w, h, radius, intensity, color)
    color = color or Theme.colors.accent
    local m = Theme.metrics
    local r, g, b = color[1], color[2], color[3]

    love.graphics.setBlendMode("add")
    for i = m.glowLayers, 1, -1 do
        local spread = i * m.glowSpread
        love.graphics.setColor(r, g, b, (m.glowAlpha * intensity) / i)
        love.graphics.rectangle("fill",
            x - spread, y - spread,
            w + spread * 2, h + spread * 2,
            radius + spread, radius + spread)
    end
    love.graphics.setBlendMode("alpha")
end

-- The standard interactive-row background, shared by button/toggle/slider/
-- selector: a pulsing glow halo when focused, a fill easing panel -> accentDark
-- with focus, and a border easing panelBorder -> accent. `glow` is the widget's
-- eased 0..1 focus amount, `time` drives the halo pulse. `alpha` (default 1)
-- fades only the border for disabled rows, matching the Selector's greyed look
-- (the fill stays opaque so the row still reads as a solid control).
function Theme.rowChrome(x, y, w, h, glow, time, alpha)
    alpha = alpha or 1
    local c, m = Theme.colors, Theme.metrics
    if glow > 0.01 then
        Theme.glowRect(x, y, w, h, m.radius, glow * Theme.pulse(time))
    end
    love.graphics.setColor(Theme.lerp(c.panel, c.accentDark, glow))
    love.graphics.rectangle("fill", x, y, w, h, m.radius, m.radius, 10)
    local br, bg, bb = Theme.lerp(c.panelBorder, c.accent, glow)
    love.graphics.setColor(br, bg, bb, alpha)
    love.graphics.rectangle("line", x, y, w, h, m.radius, m.radius, 10)
end

-- Standard panel: filled rounded rect with a border.
function Theme.panel(x, y, w, h)
    local radius = Theme.metrics.radius
    love.graphics.setColor(Theme.colors.panel)
    love.graphics.rectangle("fill", x, y, w, h, radius, radius, 8)
    love.graphics.setColor(Theme.colors.panelBorder)
    love.graphics.rectangle("line", x, y, w, h, radius, radius, 8)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Seed metrics at scale 1 so the table is never empty if something reads it
-- before love.load gets a chance to call rescale.
Theme.rescale(DESIGN_HEIGHT)

return Theme
