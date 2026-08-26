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

local NEUTRALS = {
    bg          = { 0.05, 0.05, 0.07 }, -- window clear color
    panel       = { 0.10, 0.11, 0.14 }, -- widget/panel background
    panelBorder = { 0.25, 0.28, 0.35 },
    track       = { 0.18, 0.18, 0.20 }, -- empty bar/slider track
    sliderKnob = { 0.92, 0.94, 0.98 },
    text        = { 0.92, 0.94, 0.98 },
    textMuted   = { 0.72, 0.75, 0.82 },
    textDim     = { 0.55, 0.58, 0.65 }, -- hints, footers, debug overlay
}

local TINT_STRENGTH = {
    bg          = 0.2,
    panel       = 0.75,
    panelBorder = 0.85,
    track       = 0.60,
    sliderKnob = 0.4,
    text        = 0.10,
    textMuted   = 0.22,
    textDim     = 0.35,
}

local SEMANTIC = {
    warning = { 1.00, 0.75, 0.25 },
    danger  = { 0.95, 0.35, 0.35 },
}

local ACCENT_DARK_MIX = 0.32
local DANGER_REST_MIX = 0.55
local STAR_TINT       = 0.45
local SCRIM_DARKEN    = 0.35
local SCRIM_ALPHA     = 0.62
local SHADOW_DARKEN   = 0.25 
local SHADOW_ALPHA    = 0.75

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

local function buildPalette(spec)
    local accent = spec.accent
    local colors = { accent = accent, accentAlt = spec.accentAlt }

    for name, neutral in pairs(NEUTRALS) do
        colors[name] = spec[name] or tinted(neutral, accent, TINT_STRENGTH[name] * spec.tint)
    end
    for name, color in pairs(SEMANTIC) do
        colors[name] = spec[name] or color
    end

    colors.accentDark = spec.accentDark or blend(colors.panel, accent, ACCENT_DARK_MIX)

    colors.dangerDark = spec.dangerDark or blend(colors.panel, colors.danger, ACCENT_DARK_MIX)
    colors.dangerBorder = spec.dangerBorder or
        blend(colors.panelBorder, colors.danger, DANGER_REST_MIX)

    colors.star = spec.star or blend({ 1, 1, 1 }, normalized(accent), STAR_TINT)

    local bg = colors.bg
    colors.scrim = spec.scrim or
        { bg[1] * SCRIM_DARKEN, bg[2] * SCRIM_DARKEN, bg[3] * SCRIM_DARKEN, SCRIM_ALPHA }
    colors.shadow = spec.shadow or
        { bg[1] * SHADOW_DARKEN, bg[2] * SHADOW_DARKEN, bg[3] * SHADOW_DARKEN, SHADOW_ALPHA }

    colors.titleGradient1 = spec.title[1]
    colors.titleGradient2 = spec.title[2]
    colors.titleGradient3 = spec.title[3]

    return colors
end

local PALETTES = {
    {
        -- Default pallete, Nebula
        id        = "default",
        accent    = { 0.30, 0.70, 1.00 },
        accentAlt = { 0.62, 0.40, 1.00 },
        tint      = 0.70,
        title     = { { 0.25, 0.60, 1.00 }, { 0.85, 0.92, 1.00 }, { 0.62, 0.40, 1.00 } },
    },
    {
        -- Carbon
        id        = "carbon",
        accent    = { 0.25, 0.25, 0.25 },
        accentAlt = { 0.9, 0.9, 0.9 },
        tint      = 0.70,
        title     = { { 0.4, 0.4, 0.4 }, { 0.85, 0.92, 1.00 }, { 0.2, 0.2, 0.2 } },
    },
    {
        -- "Amethyst"
        id        = "amethyst",
        accent    = { 0.4, 0.1, 0.6 },
        accentAlt = { 0.8, 0.2, 0.6 },
        tint      = 0.75,
        title     = { { 0.62, 0.25, 1.00 }, { 0.95, 0.86, 1.00 }, { 1.00, 0.40, 0.85 } },
    },
    {
        -- "Emerald" - green into teal.
        id        = "emerald",
        accent    = { 0.25, 0.92, 0.60 },
        accentAlt = { 0.35, 0.80, 1.00 },
        tint      = 0.70,
        title     = { { 0.20, 0.90, 0.55 }, { 0.88, 1.00, 0.92 }, { 0.30, 0.78, 1.00 } },
    },
    {
        -- "Lavender" - purple into pink.
        id        = "lavender",
        accent    = { 0.72, 0.32, 1.00 },
        accentAlt = { 1.00, 0.42, 0.85 },
        tint      = 0.75,
        title     = { { 0.62, 0.25, 1.00 }, { 0.95, 0.86, 1.00 }, { 1.00, 0.40, 0.85 } },
    },
    {
        -- "Topaz" - yellow into orange.
        id        = "topaz",
        accent    = { 1.00, 0.90, 0.30 },
        accentAlt = { 1.00, 0.50, 0.30 },
        tint      = 0.70,
        danger    = { 0.95, 0.10, 0.14 },
        title     = { { 1.00, 0.90, 0.30 }, { 1.00, 0.95, 0.82 }, { 1.00, 0.50, 0.30 } },
    },
    {
        -- "Ember" - the warm theme.
        id        = "ember",
        accent    = { 1.00, 0.60, 0.20 },
        accentAlt = { 1.00, 0.35, 0.45 },
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
        title     = { { 0.55, 0.62, 0.78 }, { 0.96, 0.98, 1.00 }, { 0.55, 0.62, 0.78 } },
    },
    {
        -- "Ruby"
        id        = "ruby",
        accent    = { 0.75, 0.10, 0.10 },
        accentAlt = { 1.00, 0.50, 0.30 },
        tint      = 0.5,
        danger    = { 0.95, 0.10, 0.14 },
        title     = { { 0.75, 0.10, 0.10 }, { 1.00, 0.90, 0.85 }, { 0.75, 0.20, 0.10 } },
    },
    {
       id        = "diamond",
       accent    = { 0.2, 1.00, 1.00 },
       accentAlt = { 0.52, 0.60, 0.76 },
       tint      = 0.40,
       title     = { { 0.55, 0.62, 0.78 }, { 0.96, 0.98, 1.00 }, { 0.55, 0.62, 0.78 } },
    },
    {
        id        =  "lapis",
        accent    = { 0.10, 0.30, 0.90 },
        accentAlt = { 0.52, 0.60, 0.76 },
        tint      =   0.40,
        title     = { { 0.55, 0.62, 0.78 }, { 0.96, 0.98, 1.00 }, { 0.55, 0.62, 0.78 } },
    },
    {
        id        =  "rose",
        accent    = { 0.65, 0.10, 0.35 },
        accentAlt = { 0.56, 0.250, 0.76 },
        tint      =   0.40,
        title     = { { 0.60, 0.10, 0.30 }, { 0.96, 0.98, 1.00 }, { 0.56, 0.250, 0.76 } },
    },
    -- a placeholder for future palletes.
    --{
    --    id        = "custom",
    --    accent    = { 0.30, 0.70, 1.00 },
    --    accentAlt = { 0.52, 0.60, 0.76 },
    --    tint      = 0.40,
    --    title     = { { 0.55, 0.62, 0.78 }, { 0.96, 0.98, 1.00 }, { 0.55, 0.62, 0.78 } },
    --},
}

Theme.DEFAULT = "default"

local palettes = {}
local paletteList = {}

for _, spec in ipairs(PALETTES) do
    palettes[spec.id] = buildPalette(spec)
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

local TONES = {
    accent = { rest = "panelBorder",  lit = "accent", fill = "accentDark" },
    danger = { rest = "dangerBorder", lit = "danger", fill = "dangerDark" },
}

function Theme.rowChrome(x, y, w, h, glow, time, alpha, tone)
    alpha = alpha or 1
    local c, m = Theme.colors, Theme.metrics
    local set = TONES[tone] or TONES.accent
    local lit = c[set.lit]

    if glow > 0.01 then
        Theme.glowRect(x, y, w, h, m.radius, glow * Theme.pulse(time), lit)
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
