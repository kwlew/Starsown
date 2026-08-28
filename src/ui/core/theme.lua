-- src/ui/core/theme.lua

local Math = require "utils.math"

local Theme = {}

local FONT_FAMILIES = {
    acme = "assets/fonts/Acme/",
    oxanium  = "assets/fonts/Oxanium/",
    orbitron = "assets/fonts/Orbitron/static/",
    play     = "assets/fonts/Play/", -- Cyrillic fallback only, see fontRoles' `fallback` field
}
local DEFAULT_FAMILY = "oxanium"

Theme.colors = {} 

-- Palette spec: `accent` is the only required field. Optional knobs are
-- `accentAlt`, `neutralHue` (what the greys lean toward, default `accent`),
-- `tint` (one scalar, or a per-role table carrying a `default`), `title`
-- (omit to derive from the accent pair), and a raw override for any role by
-- name. Every palette must produce the same key set -- see assertRoles.

local NEUTRALS = {
    bg          = { 0.05, 0.05, 0.07 },
    panel       = { 0.10, 0.11, 0.14 },
    panelRaised = { 0.14, 0.15, 0.19 },
    panelBorder = { 0.25, 0.28, 0.35 },
    track       = { 0.18, 0.18, 0.20 },
    knob        = { 0.78, 0.80, 0.86 }, -- slider + toggle knobs
    text        = { 0.92, 0.94, 0.98 },
    textMuted   = { 0.72, 0.75, 0.82 },
    textDim     = { 0.55, 0.58, 0.65 },
    highlight   = { 0.80, 0.80, 0.82 },
    cursor      = { 0.95, 0.95, 0.97 },
}

-- how far each neutral travels toward the hue at tint = 1; `tint` scales these
local TINT_STRENGTH = {
    bg          = 0.2,
    panel       = 0.75,
    panelRaised = 0.80,
    panelBorder = 0.85,
    track       = 0.60,
    knob        = 0.45,
    text        = 0.10,
    textMuted   = 0.22,
    textDim     = 0.35,
    highlight   = 0.20,
    cursor      = 0.35,
}

local SEMANTIC = {
    warning = { 1.00, 0.75, 0.25 },
    danger  = { 0.95, 0.35, 0.35 },
    success = { 0.35, 0.85, 0.45 },
    info    = { 0.40, 0.70, 1.00 },
}

local ACCENT_DARK_MIX   = 0.32
local ACCENT_SOFT_MIX   = 0.50
local ACCENT_BRIGHT_MIX = 0.35 -- toward white, not toward accent: a near-black accent has no headroom
local ACCENT_DIM_MIX    = 0.30 -- toward black, for filled controls where full accent glares
local DANGER_REST_MIX   = 0.55
local STAR_TINT         = 0.45
local TITLE_CENTER_TINT = 0.14
local SCRIM_DARKEN      = 0.35
local SCRIM_ALPHA       = 0.62
local SHADOW_DARKEN     = 0.25
local SHADOW_ALPHA      = 0.75

Theme.fixedColors = {
    starPop = { 1, 0.5, 0.2 },
    gold = { 1, 0.82, 0.35 },
    goldFlare = { 1, 0.60, 0.12 },
}

local function luminance(r, g, b)
    return 0.30 * r + 0.59 * g + 0.11 * b
end

local function mix(a, b, t)
    return Math.clamp01(a + (b - a) * t)
end

local function blend(a, b, t)
    return { mix(a[1], b[1], t), mix(a[2], b[2], t), mix(a[3], b[3], t) }
end

local function normalized(color)
    local peak = math.max(color[1], color[2], color[3])
    if peak <= 0 then return { 0, 0, 0 } end
    return { color[1] / peak, color[2] / peak, color[3] / peak }
end

local function tinted(base, hue, amount)
    local peak = math.max(hue[1], hue[2], hue[3])
    if peak <= 0 or amount <= 0 then
        return { base[1], base[2], base[3] }
    end

    local nr, ng, nb = hue[1] / peak, hue[2] / peak, hue[3] / peak
    local k = luminance(base[1], base[2], base[3]) / luminance(nr, ng, nb)

    return {
        mix(base[1], Math.clamp01(nr * k), amount),
        mix(base[2], Math.clamp01(ng * k), amount),
        mix(base[3], Math.clamp01(nb * k), amount),
    }
end

-- one scalar, or per-role multipliers where `default` covers the rest
local function tintAmounts(tint)
    local amounts = {}
    local perRole = type(tint) == "table"
    local fallback = perRole and (tint.default or 1) or (tint or 1)

    for name, base in pairs(TINT_STRENGTH) do
        amounts[name] = base * (perRole and (tint[name] or fallback) or fallback)
    end
    return amounts
end

local function buildPalette(spec)
    local accent = spec.accent
    local accentAlt = spec.accentAlt or accent
    local hue = spec.neutralHue or accent -- surfaces need not share the accent's temperature
    local amount = tintAmounts(spec.tint)

    local colors = { accent = accent, accentAlt = accentAlt }

    for name, neutral in pairs(NEUTRALS) do
        colors[name] = spec[name] or tinted(neutral, hue, amount[name])
    end
    for name, color in pairs(SEMANTIC) do
        colors[name] = spec[name] or color
    end

    colors.accentDark = spec.accentDark or blend(colors.panel, accent, ACCENT_DARK_MIX)
    colors.accentSoft = spec.accentSoft or blend(colors.panel, accent, ACCENT_SOFT_MIX)
    colors.accentBright = spec.accentBright or blend(accent, { 1, 1, 1 }, ACCENT_BRIGHT_MIX)
    colors.accentDim = spec.accentDim or blend(accent, { 0, 0, 0 }, ACCENT_DIM_MIX)
    colors.glow = spec.glow or accent

    colors.dangerDark = spec.dangerDark or blend(colors.panel, colors.danger, ACCENT_DARK_MIX)
    colors.dangerBorder = spec.dangerBorder or
        blend(colors.panelBorder, colors.danger, DANGER_REST_MIX)

    colors.star = spec.star or blend({ 1, 1, 1 }, normalized(accent), STAR_TINT)

    local bg = colors.bg
    colors.scrim = spec.scrim or
        { bg[1] * SCRIM_DARKEN, bg[2] * SCRIM_DARKEN, bg[3] * SCRIM_DARKEN, SCRIM_ALPHA }
    colors.shadow = spec.shadow or
        { bg[1] * SHADOW_DARKEN, bg[2] * SHADOW_DARKEN, bg[3] * SHADOW_DARKEN, SHADOW_ALPHA }

    local title = spec.title or
        { accent, blend({ 1, 1, 1 }, normalized(accentAlt), TITLE_CENTER_TINT), accentAlt }
    colors.titleGradient1 = title[1]
    colors.titleGradient2 = title[2]
    colors.titleGradient3 = title[3]

    return colors
end

local PALETTES = {
    {
        -- Default pallete, Nebula
        id        = "default",
        accent    = { 0.34, 0.68, 0.96 },
        accentAlt = { 0.62, 0.42, 0.98 },
        tint      = 0.70,
        title     = { { 0.25, 0.60, 1.00 }, { 0.85, 0.92, 1.00 }, { 0.62, 0.40, 1.00 } },
    },
    {
        -- Carbon. A grey hue normalizes to white, so tinting toward this
        -- accent would do nothing; neutralHue casts the surfaces instead.
        -- glow/accentDim are overridden because a near-black accent neither
        -- blooms additively nor stays visible once dimmed against the track.
        id         = "carbon",
        accent     = { 0.32, 0.33, 0.36 },
        accentAlt  = { 0.90, 0.90, 0.92 },
        neutralHue = { 0.55, 0.62, 0.78 },
        tint       = 0.70,
        glow       = { 0.75, 0.78, 0.85 },
        accentDim  = { 0.52, 0.55, 0.62 },
        title      = { { 0.42, 0.44, 0.48 }, { 0.85, 0.92, 1.00 }, { 0.34, 0.36, 0.40 } },
    },
    {
        -- "Amethyst" - deep violet into magenta. Its title stops were a copy
        -- of lavender's, which made the two themes share a wordmark; derived.
        id        = "amethyst",
        accent    = { 0.52, 0.18, 0.72 },
        accentAlt = { 0.82, 0.26, 0.66 },
        tint      = 0.75,
    },
    {
        -- "Emerald" - green into teal.
        id        = "emerald",
        accent    = { 0.30, 0.82, 0.56 },
        accentAlt = { 0.36, 0.76, 0.96 },
        tint      = 0.70,
        title     = { { 0.20, 0.90, 0.55 }, { 0.88, 1.00, 0.92 }, { 0.30, 0.78, 1.00 } },
    },
    {
        -- "Lavender" - purple into pink.
        id        = "lavender",
        accent    = { 0.68, 0.38, 0.95 },
        accentAlt = { 0.95, 0.46, 0.82 },
        tint      = 0.75,
        title     = { { 0.62, 0.25, 1.00 }, { 0.95, 0.86, 1.00 }, { 1.00, 0.40, 0.85 } },
    },
    {
        -- "Topaz" - yellow into orange. Text takes a fraction of the surface
        -- tint: pulled the full distance toward yellow it goes sallow.
        id        = "topaz",
        accent    = { 0.95, 0.80, 0.32 },
        accentAlt = { 0.96, 0.52, 0.30 },
        tint      = { default = 0.70, text = 0.25, textMuted = 0.30, textDim = 0.40 },
        danger    = { 0.95, 0.10, 0.14 },
        title     = { { 1.00, 0.90, 0.30 }, { 1.00, 0.95, 0.82 }, { 1.00, 0.50, 0.30 } },
    },
    {
        -- "Ember" - the warm theme.
        id        = "ember",
        accent    = { 0.96, 0.58, 0.22 },
        accentAlt = { 0.96, 0.36, 0.44 },
        tint      = 0.70,
        warning   = { 1.00, 0.88, 0.48 },
        danger    = { 1.00, 0.26, 0.30 },
        title     = { { 1.00, 0.72, 0.25 }, { 1.00, 0.95, 0.82 }, { 1.00, 0.38, 0.32 } },
    },
    {
        -- "Slate"
        id        = "slate",
        accent    = { 0.70, 0.78, 0.92 },
        accentAlt = { 0.52, 0.60, 0.76 },
        tint      = 0.40,
    },
    {
        -- "Ruby". danger is lifted off the accent so a Quit row still reads as
        -- a warning rather than as more theme.
        id        = "ruby",
        accent    = { 0.80, 0.18, 0.20 },
        accentAlt = { 0.96, 0.52, 0.32 },
        tint      = 0.5,
        danger    = { 0.98, 0.32, 0.30 },
        title     = { { 0.75, 0.10, 0.10 }, { 1.00, 0.90, 0.85 }, { 0.75, 0.20, 0.10 } },
    },
    {
        -- "Diamond" - icy cyan. Was a pure { 0.2, 1, 1 }: two channels pinned
        -- at full, which glared on every filled control.
        id        = "diamond",
        accent    = { 0.45, 0.86, 0.94 },
        accentAlt = { 0.68, 0.94, 1.00 },
        tint      = 0.45,
    },
    {
        -- "Lapis" - deep blue, lifted off pure navy so accentDim stays clear
        -- of the track it fills.
        id        = "lapis",
        accent    = { 0.30, 0.48, 0.92 },
        accentAlt = { 0.42, 0.70, 1.00 },
        tint      = 0.45,
    },
    {
        -- "Rose" - A shade of pink.
        id        = "rose",
        accent    = { 0.76, 0.22, 0.44 },
        accentAlt = { 0.62, 0.30, 0.80 },
        tint      = 0.45,
    },
    -- a placeholder for future palletes. `accent` is the only required field;
    -- omit `title` to derive the wordmark from the accent pair.
    --{
    --    id        = "custom",
    --    accent    = { 0.30, 0.70, 1.00 },
    --    accentAlt = { 0.52, 0.60, 0.76 },
    --    tint      = 0.40,
    --},
}

Theme.DEFAULT = "default"

local palettes = {}
local paletteList = {}

-- applyPalette writes into the live color tables rather than replacing them,
-- so a role missing from one palette keeps the outgoing theme's value after a
-- switch. A typo'd override is how that happens; catch it at load instead.
local function assertRoles(reference, referenceId, palette, id)
    for name in pairs(reference) do
        assert(palette[name], "Theme: palette '" .. id .. "' is missing role '" ..
            name .. "' that '" .. referenceId .. "' defines")
    end
    for name in pairs(palette) do
        assert(reference[name], "Theme: palette '" .. id .. "' defines role '" ..
            name .. "' that '" .. referenceId .. "' does not -- likely a typo in its spec")
    end
end

local firstId, firstPalette
for _, spec in ipairs(PALETTES) do
    local palette = buildPalette(spec)
    if firstPalette then
        assertRoles(firstPalette, firstId, palette, spec.id)
    else
        firstId, firstPalette = spec.id, palette
    end
    palettes[spec.id] = palette
    paletteList[#paletteList + 1] = { id = spec.id }
end

Theme.current = Theme.DEFAULT

local function applyPalette(palette)
    for name, color in pairs(palette) do
        local live = Theme.colors[name]
        if live then
            live[1], live[2], live[3], live[4] = color[1], color[2], color[3], color[4]
        else
            Theme.colors[name] = { color[1], color[2], color[3], color[4] }
        end
    end
end

function Theme.available()
    return paletteList
end

function Theme.setTheme(id)
    if not palettes[id] then id = Theme.DEFAULT end
    if id == Theme.current then return false end

    Theme.current = id
    applyPalette(palettes[id])
    love.graphics.setBackgroundColor(Theme.colors.bg) 
    return true
end

function Theme.titleGradient()
    return { Theme.colors.titleGradient1, Theme.colors.titleGradient2, Theme.colors.titleGradient3 }
end

local baseMetrics = {
    radius     = 8,
    padding    = 14,
    rowHeight  = 48,
    rowGap     = 14,
    glowSpread = 3,
}

local constantMetrics = {
    glowLayers = 3,
    glowAlpha  = 0.16,
    focusSpeed = 10,
}

local fontRoles = {
    title = { file = "Orbitron-ExtraBold.ttf", family = "orbitron", size = 80 }, -- game title
    title2 = { file = "Acme9_TITLE.ttf", family = "acme", size = 52  }, -- game title, alternate
    heading = { file = "Oxanium-Bold.ttf",      size = 40, fallback = "Play-Bold.ttf" },
    button  = { file = "Oxanium-SemiBold.ttf",  size = 26, fallback = "Play-Bold.ttf" },
    body    = { file = "Oxanium-Medium.ttf",    size = 26, fallback = "Play-Regular.ttf" },
    small   = { file = "Oxanium-Regular.ttf",   size = 15, fallback = "Play-Regular.ttf" },
    debug   = { file = "Oxanium-Medium.ttf",    size = 14, fallback = "Play-Regular.ttf" },
}

Theme.metrics = {}
Theme.scale = 0 

local DESIGN_HEIGHT = 720

local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.85, 1.6, 0.05

local fontCache = {}

local function scaleForHeight(height)
    local s = Math.clamp(height / DESIGN_HEIGHT, SCALE_MIN, SCALE_MAX)
    return Math.round(s / SCALE_STEP) * SCALE_STEP
end

function Theme.rescale(height)
    local s = scaleForHeight(height or love.graphics.getHeight())
    if s == Theme.scale then return false end
    Theme.scale = s

    for key, value in pairs(baseMetrics) do
        Theme.metrics[key] = Math.round(value * s)
    end
    for key, value in pairs(constantMetrics) do
        Theme.metrics[key] = value
    end

    fontCache = {}
    return true
end

function Theme.px(value)
    return Math.round(value * Theme.scale)
end

function Theme.font(name)
    local role = fontRoles[name]
    assert(role, "Theme.font: unknown font '" .. tostring(name) .. "'")
    if not fontCache[name] then
        local size = math.max(1, Math.round(role.size * Theme.scale))
        local dir = FONT_FAMILIES[role.family or DEFAULT_FAMILY]
        assert(dir, "Theme.font: role '" .. name .. "' names unknown family '" .. tostring(role.family) .. "'")

        local ok, font = pcall(love.graphics.newFont, dir .. role.file, size)
        font = ok and font or love.graphics.newFont(size)
        fontCache[name] = font

        if role.fallback then
            local fbOk, fallback = pcall(love.graphics.newFont, FONT_FAMILIES.play .. role.fallback, size)
            if fbOk then font:setFallbacks(fallback) end
        end
    end
    return fontCache[name]
end

function Theme.fontRoles()
    local names = {}
    for name in pairs(fontRoles) do names[#names + 1] = name end
    table.sort(names)
    return names
end

function Theme.fontFor(font, defaultRole)
    if type(font) == "userdata" then return font end
    return Theme.font(type(font) == "string" and font or defaultRole)
end

function Theme.setColor(color, alpha)
    love.graphics.setColor(color[1], color[2], color[3], alpha or color[4] or 1)
end

function Theme.lerp(a, b, t)
    return a[1] + (b[1] - a[1]) * t,
           a[2] + (b[2] - a[2]) * t,
           a[3] + (b[3] - a[3]) * t
end

function Theme.pointIn(px, py, x, y, w, h)
    return px >= x and px <= x + w and py >= y and py <= y + h
end

function Theme.approach(current, target, dt, speed)
    return current + (target - current) * math.min(dt * (speed or Theme.metrics.focusSpeed), 1)
end

function Theme.pulse(time)
    return 0.75 + 0.25 * math.sin(time * 3)
end

function Theme.centerY(y, h, font)
    return y + (h - font:getHeight()) / 2
end

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

function Theme.resolveLabel(label, owner)
    if type(label) == "function" then
        return label(owner)
    end
    return label or ""
end

function Theme.glowRect(x, y, w, h, radius, intensity, color)
    color = color or Theme.colors.glow
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

-- `glow` is separate from `lit` so an accent too dark to bloom additively
-- (carbon) can still show a focus ring
local TONES = {
    accent = { rest = "panelBorder",  lit = "accent", fill = "accentDark", glow = "glow" },
    danger = { rest = "dangerBorder", lit = "danger", fill = "dangerDark", glow = "danger" },
}

function Theme.rowChrome(x, y, w, h, glow, time, alpha, tone)
    alpha = alpha or 1
    local c, m = Theme.colors, Theme.metrics
    local set = TONES[tone] or TONES.accent
    local lit = c[set.lit]

    if glow > 0.01 then
        Theme.glowRect(x, y, w, h, m.radius, glow * Theme.pulse(time), c[set.glow])
    end
    love.graphics.setColor(Theme.lerp(c.panel, c[set.fill], glow))
    love.graphics.rectangle("fill", x, y, w, h, m.radius, m.radius, 10)
    local br, bg, bb = Theme.lerp(c[set.rest], lit, glow)
    love.graphics.setColor(br, bg, bb, alpha)
    love.graphics.rectangle("line", x, y, w, h, m.radius, m.radius, 10)
end

function Theme.panel(x, y, w, h)
    local radius = Theme.metrics.radius
    love.graphics.setColor(Theme.colors.panel)
    love.graphics.rectangle("fill", x, y, w, h, radius, radius, 8)
    love.graphics.setColor(Theme.colors.panelBorder)
    love.graphics.rectangle("line", x, y, w, h, radius, radius, 8)
    love.graphics.setColor(1, 1, 1, 1)
end

applyPalette(palettes[Theme.DEFAULT])
Theme.rescale(DESIGN_HEIGHT)

return Theme
