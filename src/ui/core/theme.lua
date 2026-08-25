-- The style contract for the whole game: every color, font, and metric the UI
-- uses lives here. Widgets and states must never hardcode style values -- ask the theme.
--
-- Everything sized in pixels is expressed at a 720p design height and scaled
-- by Theme.scale (see Theme.rescale), so the UI keeps its proportions from
-- 768p up to 1080p instead of shrinking into the middle of a big screen.
--
-- Colors come from the palette the player picked in Options:
--
--   Theme.setTheme("ember")   -- swap the active palette
--   Theme.colors.accent       -- always the *active* palette's accent
--   Theme.available()         -- { {id="default"}, ... } for a selector
--
-- Theme.colors is rewritten in place on a theme switch, never swapped out (see applyPalette).

local Math = require "utils.math"

local Theme = {}

-- static/ is Orbitron's individually-cut weights; the bare .ttf one level up
-- is a variable font that LÖVE 11.5 always renders at one default weight, so
-- static is what a role should point at
local FONT_FAMILIES = {
    acme = "assets/fonts/Acme/",
    oxanium  = "assets/fonts/Oxanium/",
    orbitron = "assets/fonts/Orbitron/static/",
}
local DEFAULT_FAMILY = "oxanium"

Theme.colors = {} -- live palette; populated by applyPalette, never assigned to directly

-- the neutral ramp every palette is built from; a palette only says how hard
-- these lean toward its own accent, so themes stay siblings of one design
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

-- how far each neutral leans toward the accent hue at tint = 1; bg stays
-- near-black for the night sky to read, body text stays text
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

-- same in every palette: "this button destroys something" isn't a property
-- of the skin; a palette can still override by naming it in its spec (see `ember`)
local SEMANTIC = {
    warning = { 1.00, 0.75, 0.25 },
    danger  = { 0.95, 0.35, 0.35 },
}

-- mixes behind the derived colors, all 0..1
local ACCENT_DARK_MIX = 0.32 -- panel -> accent, for a focused widget's fill
local DANGER_REST_MIX = 0.55 -- panelBorder -> danger, for a destructive row at rest
local STAR_TINT       = 0.45 -- white -> accent, for the night sky
local SCRIM_DARKEN    = 0.35 -- of bg, for the modal scrim
local SCRIM_ALPHA     = 0.62
local SHADOW_DARKEN   = 0.25 -- of bg, for text drop shadows
local SHADOW_ALPHA    = 0.75

-- palette-independent by design: a golden star reads as gold in every theme,
-- so these never go through tinted() the way Theme.colors.* do
Theme.fixedColors = {
    starPop = { 1, 0.5, 0.2 },       -- the debris from a popped star
    gold = { 1, 0.82, 0.35 },        -- a golden star, and its count on the stats screen
    goldFlare = { 1, 0.60, 0.12 },   -- the hotter core of that star's streak
}

-- perceived brightness (Rec. 601), used to hold a neutral's lightness fixed while its hue moves
local function luminance(r, g, b)
    return 0.30 * r + 0.59 * g + 0.11 * b
end

local function mix(a, b, t)
    return Math.clamp01(a + (b - a) * t)
end

-- component-wise mix, new table (Theme.lerp is the same math for the draw
-- path, returning three values to avoid the alloc)
local function blend(a, b, t)
    return { mix(a[1], b[1], t), mix(a[2], b[2], t), mix(a[3], b[3], t) }
end

-- pushed to full brightness for mixing into light colors: mixing white
-- toward a dim accent only greys it out, never tints it
local function normalized(color)
    local peak = math.max(color[1], color[2], color[3])
    if peak <= 0 then return { 0, 0, 0 } end
    return { color[1] / peak, color[2] / peak, color[3] / peak }
end

-- mixes `base` toward `hue` by `amount` without changing base's own
-- brightness: hue is normalized then rescaled to base's luminance before the
-- mix. That's what makes the near-black background tintable at all -- a
-- plain lerp toward a neon accent would grey it out long before the hue
-- shows. Clamped per channel, so a near-white neutral just desaturates
-- instead of blowing out.
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

-- expands a palette spec into the flat color table the UI reads; every
-- palette gets the same keys, so a theme switch can overwrite the live
-- table in place with nothing stranded from the old one
local function buildPalette(spec)
    local accent = spec.accent
    local colors = { accent = accent, accentAlt = spec.accentAlt }

    for name, neutral in pairs(NEUTRALS) do
        colors[name] = spec[name] or tinted(neutral, accent, TINT_STRENGTH[name] * spec.tint)
    end
    for name, color in pairs(SEMANTIC) do
        colors[name] = spec[name] or color
    end

    -- focused-widget background: panel carried toward accent, so a lit row still reads as a panel
    colors.accentDark = spec.accentDark or blend(colors.panel, accent, ACCENT_DARK_MIX)

    -- danger's counterparts (see TONES): a destructive row lights up in
    -- these and carries dangerBorder at rest, so it reads as different before it's ever focused
    colors.dangerDark = spec.dangerDark or blend(colors.panel, colors.danger, ACCENT_DARK_MIX)
    colors.dangerBorder = spec.dangerBorder or
        blend(colors.panelBorder, colors.danger, DANGER_REST_MIX)

    colors.star = spec.star or blend({ 1, 1, 1 }, normalized(accent), STAR_TINT)

    -- both carry their own alpha (Theme.setColor reads color[4])
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

-- The themes the player can choose, in selector order. Each is authored as a
-- handful of decisions (accent pair, how hard neutrals lean toward it, three
-- title gradient stops) and buildPalette derives the rest; any derived key
-- can still be pinned by naming it in the spec. Display names are localized,
-- keyed on `id` (options.themeName.<id>).
local PALETTES = {
    {
        -- "Nebula" — the game's original.
        id        = "default",
        accent    = { 0.30, 0.70, 1.00 }, -- focus, fills, glow
        accentAlt = { 0.62, 0.40, 1.00 }, -- violet partner for gradients and gas
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
        -- "Emerald" — green into teal.
        id        = "emerald",
        accent    = { 0.25, 0.92, 0.60 },
        accentAlt = { 0.35, 0.80, 1.00 },
        tint      = 0.70,
        title     = { { 0.20, 0.90, 0.55 }, { 0.88, 1.00, 0.92 }, { 0.30, 0.78, 1.00 } },
    },
    {
        -- "Lavender" — purple into pink.
        id        = "lavender",
        accent    = { 0.72, 0.32, 1.00 },
        accentAlt = { 1.00, 0.42, 0.85 },
        tint      = 0.75,
        title     = { { 0.62, 0.25, 1.00 }, { 0.95, 0.86, 1.00 }, { 1.00, 0.40, 0.85 } },
    },
    {
        -- "Topaz" — yellow into orange.
        id        = "topaz",
        accent    = { 1.00, 0.90, 0.30 },
        accentAlt = { 1.00, 0.50, 0.30 },
        tint      = 0.70,
        danger    = { 0.95, 0.10, 0.14 },
        title     = { { 1.00, 0.90, 0.30 }, { 1.00, 0.95, 0.82 }, { 1.00, 0.50, 0.30 } },
    },
    {
        -- "Ember" — the warm theme.
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
        accent    = { 1.00, 0.30, 0.50 },
        accentAlt = { 1.00, 0.50, 0.30 },
        tint      = 0.5,
        danger    = { 0.95, 0.10, 0.14 },
        title     = { { 1.00, 0.30, 0.50 }, { 1.00, 0.90, 0.85 }, { 1.00, 0.50, 0.30 } },
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
    -- a placeholder for a palette the player built in Options
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
    heading = { file = "Oxanium-Bold.ttf",      size = 40 },
    button  = { file = "Oxanium-SemiBold.ttf",  size = 26 },
    body    = { file = "Oxanium-Medium.ttf",    size = 26 },
    small   = { file = "Oxanium-Regular.ttf",   size = 15 },
    debug   = { file = "Oxanium-Medium.ttf",    size = 14 },
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

-- recomputes scale from window height, rebuilds metrics, drops the font
-- cache. Call from love.load and love.resize. Fonts resolve per draw (see
-- Theme.fontFor) so most widgets pick up the new size on their own, but
-- anything that cached a Font or a newText mesh itself (TextFactory) must
-- rebuild when this returns true.
function Theme.rescale(height)
    local s = scaleForHeight(height or love.graphics.getHeight())
    if s == Theme.scale then return false end
    Theme.scale = s

    for key, value in pairs(baseMetrics) do -- mutated in place; widgets/states hold references
        Theme.metrics[key] = Math.round(value * s)
    end
    for key, value in pairs(constantMetrics) do
        Theme.metrics[key] = value
    end

    fontCache = {}
    return true
end

-- scales a caller's own design-space pixel constant; use for any literal px value outside Theme.metrics
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
        -- fall back to LÖVE's default font if the .ttf can't open, so a
        -- missing font file degrades instead of crashing
        local ok, font = pcall(love.graphics.newFont, dir .. role.file, size)
        fontCache[name] = ok and font or love.graphics.newFont(size)
    end
    return fontCache[name]
end

-- every role name, so the loading screen can warm the whole cache in one
-- pass without naming each role and drifting out of sync with this file
function Theme.fontRoles()
    local names = {}
    for name in pairs(fontRoles) do names[#names + 1] = name end
    table.sort(names)
    return names
end

-- resolved at draw time rather than in a widget's constructor: a Font object
-- captured at construction survives a rescale and leaves that widget stuck at the old size
--
--   font = nil       -> the widget's default role
--   font = "heading" -> that role, resolved fresh each draw (scale-aware)
--   font = <Font>    -> that exact font, caller owns keeping it in scale
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

-- frame-rate-independent eased step, the widgets' shared glow/knob/highlight
-- animation; `speed` defaults to the shared focus rate
function Theme.approach(current, target, dt, speed)
    return current + (target - current) * math.min(dt * (speed or Theme.metrics.focusSpeed), 1)
end

-- shared 0.5..1 breathing pulse for every focused glow, driven by a widget's own accumulated time
function Theme.pulse(time)
    return 0.75 + 0.25 * math.sin(time * 3)
end

function Theme.centerY(y, h, font)
    return y + (h - font:getHeight()) / 2
end

-- font stack, so a widget draw doesn't repeat the getFont/setFont/restore
-- dance (not a callback form: that allocates a closure per widget per frame
-- to scope two lines of drawing)
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

-- a label may be a plain string or function(owner) -> string; a function
-- label re-reads the active language every draw, so a language switch needs no rebuild
function Theme.resolveLabel(label, owner)
    if type(label) == "function" then
        return label(owner)
    end
    return label or ""
end

-- soft additive halo around a rounded rect (the loading bar's glow,
-- generalized); intensity scales brightness, color defaults to accent
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

-- named by key rather than holding color tables, so this stays a plain
-- constant a theme switch (which rewrites Theme.colors in place) never has to invalidate
local TONES = {
    accent = { rest = "panelBorder",  lit = "accent", fill = "accentDark" },
    danger = { rest = "dangerBorder", lit = "danger", fill = "dangerDark" },
}

-- standard interactive-row background shared by button/toggle/slider/
-- selector: pulsing glow when focused, fill easing panel -> the tone's dark
-- with focus, border easing the tone's rest color -> its lit one. `glow` is
-- the widget's eased 0..1 focus amount, `time` drives the pulse. `alpha`
-- (default 1) fades only the border for disabled rows, so the fill stays
-- opaque and the row still reads as a solid control. `tone` is "accent" or
-- "danger" -- a danger row leans red even at rest so the difference
-- registers before the label's been read (see Widget's `danger` flag).
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

-- seeds colors/metrics so neither is empty if something reads one before
-- love.load calls setTheme/rescale; goes through applyPalette rather than
-- setTheme since this runs at require time, too early for love.graphics state
applyPalette(palettes[Theme.DEFAULT])
Theme.rescale(DESIGN_HEIGHT)

return Theme
