-- src/ui/theme.lua
-- The style contract for the whole game: every color, font, and metric the UI
-- uses lives here, so changing the game's look means editing this file only.
-- Widgets and states must never hardcode style values — ask the theme.
--
-- Everything sized in pixels is expressed at a 720p design height and scaled by
-- Theme.scale (see Theme.rescale), so the UI keeps its proportions from 768p up
-- to 1080p instead of shrinking into the middle of a big screen.
--
-- Colors come from the palette the player picked in Options:
--
--   Theme.setTheme("ember")   -- swap the active palette
--   Theme.colors.accent       -- always the *active* palette's accent
--   Theme.available()         -- { {id="default"}, ... } for a selector
--
-- Theme.colors is a flat table of {r, g, b} (a few carry a fourth alpha), and it
-- is rewritten in place on a theme switch, never swapped out — see applyPalette.

local Math = require "utils.math"

local Theme = {}

-- Where each UI font family lives, keyed by a short name fontRoles refers to
-- below. Most roles share one family and pick their own weight from it — a
-- single weight for every role is what makes dense screens read as noise, so
-- headings/buttons get the heavy cuts and body/hint text gets the light ones —
-- but a role can name a different family (a display face for the title, say)
-- and it's just another entry here. static/ is Orbitron's individually-cut
-- weights; its bare .ttf one level up is a variable font, which LÖVE 11.5 can
-- open but always renders at a single default weight, so the static cuts are
-- the ones worth pointing a role at.
local FONT_FAMILIES = {
    acme = "assets/fonts/Acme/",
    oxanium  = "assets/fonts/Oxanium/",
    orbitron = "assets/fonts/Orbitron/static/",
}
local DEFAULT_FAMILY = "oxanium"

-- The live palette. Populated by applyPalette below; never assign to this table
-- itself (see applyPalette for why).
Theme.colors = {}

-- The neutral ramp every palette is built from: the greys that carry the UI's
-- structure. A palette doesn't restate these, it only says how hard they lean
-- toward its own accent, so the themes stay siblings rather than five separate
-- designs that happen to share a widget set.
local NEUTRALS = {
    bg          = { 0.05, 0.05, 0.07 }, -- window clear color
    panel       = { 0.10, 0.11, 0.14 }, -- widget/panel background
    panelBorder = { 0.25, 0.28, 0.35 },
    track       = { 0.18, 0.18, 0.20 }, -- empty bar/slider track
    sliderKnob = { 0.92, 0.94, 0.98 }, -- the knob on a slider track
    text        = { 0.92, 0.94, 0.98 },
    textMuted   = { 0.72, 0.75, 0.82 }, -- secondary text that still reads as text
    textDim     = { 0.55, 0.58, 0.65 }, -- hints, footers, debug overlay
}

-- How far each neutral leans toward the accent hue at a palette tint of 1.
-- Borders and panels carry most of the theme: the background has to stay
-- near-black for the night sky to read against it, and body text has to stay
-- text rather than turn into a second highlight color.
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

-- Deliberately the same in every palette: "this button destroys something" must
-- not be a property of the skin the player happens to be wearing. A palette
-- whose accent sits on top of one of these overrides it by name (see `ember`).
local SEMANTIC = {
    warning = { 1.00, 0.75, 0.25 },
    danger  = { 0.95, 0.35, 0.35 },
}

-- Mixes behind the derived colors, all 0..1.
local ACCENT_DARK_MIX = 0.32 -- panel -> accent, for a focused widget's fill
local DANGER_REST_MIX = 0.55 -- panelBorder -> danger, for a destructive row at rest
local STAR_TINT       = 0.45 -- white -> accent, for the night sky
local SCRIM_DARKEN    = 0.35 -- of bg, for the modal scrim
local SCRIM_ALPHA     = 0.62
local SHADOW_DARKEN   = 0.25 -- of bg, for text drop shadows
local SHADOW_ALPHA    = 0.75

Theme.fixedColors = {
    starPop = { 1, 0.5, 0.2 }, -- the debris from a popped star
}

-- Perceived brightness (Rec. 601), used to hold a neutral's lightness fixed
-- while its hue is moved.
local function luminance(r, g, b)
    return 0.30 * r + 0.59 * g + 0.11 * b
end

local function mix(a, b, t)
    return Math.clamp01(a + (b - a) * t)
end

-- Component-wise mix of two colors, returning a new table. (Theme.lerp is the
-- same math for the draw path, where returning three values avoids the alloc.)
local function blend(a, b, t)
    return { mix(a[1], b[1], t), mix(a[2], b[2], t), mix(a[3], b[3], t) }
end

-- A color pushed up to full brightness, for mixing into light colors: mixing
-- white toward a dim accent only greys it out, it never tints it.
local function normalized(color)
    local peak = math.max(color[1], color[2], color[3])
    if peak <= 0 then return { 0, 0, 0 } end
    return { color[1] / peak, color[2] / peak, color[3] / peak }
end

-- Mixes `base` toward `hue` by `amount` *without changing how bright base is*:
-- the hue is normalized and then rescaled to base's own luminance before the
-- mix. That is what makes the near-black background tintable at all — a plain
-- lerp toward a neon accent lifts it into a visible grey long before the hue
-- shows. Clamped per channel, so a near-white neutral pulled toward a saturated
-- hue just desaturates as far as it can instead of blowing out.
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

-- Expands a palette spec into the flat color table the UI actually reads. Every
-- palette comes out with the same set of keys, which is what lets a theme
-- switch overwrite the live table in place without leaving a color from the
-- previous theme stranded in it.
local function buildPalette(spec)
    local accent = spec.accent
    local colors = { accent = accent, accentAlt = spec.accentAlt }

    for name, neutral in pairs(NEUTRALS) do
        colors[name] = spec[name] or tinted(neutral, accent, TINT_STRENGTH[name] * spec.tint)
    end
    for name, color in pairs(SEMANTIC) do
        colors[name] = spec[name] or color
    end

    -- Focused-widget background: the panel carried toward the accent, so a lit
    -- row still reads as a panel that lit up rather than as a slab of accent.
    colors.accentDark = spec.accentDark or blend(colors.panel, accent, ACCENT_DARK_MIX)

    -- The danger tone's counterparts (see TONES): a destructive row lights up
    -- in these instead of the accent's, and carries dangerBorder at rest so it
    -- reads as different before it's ever focused.
    colors.dangerDark = spec.dangerDark or blend(colors.panel, colors.danger, ACCENT_DARK_MIX)
    colors.dangerBorder = spec.dangerBorder or
        blend(colors.panelBorder, colors.danger, DANGER_REST_MIX)

    -- The fixed stars, tinted so the backdrop belongs to the theme too.
    colors.star = spec.star or blend({ 1, 1, 1 }, normalized(accent), STAR_TINT)

    -- Both carry their own alpha (Theme.setColor reads color[4]): a scrim and a
    -- drop shadow are only ever drawn at one opacity.
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

-- The themes the player can choose, in selector order.
--
-- A palette is authored as a handful of decisions rather than as eighteen
-- triples: the accent pair the whole UI is built around, how hard the neutrals
-- lean toward it, and the three stops the wordmark cycles through. buildPalette
-- derives the rest — which is what keeps the themes consistent with each other,
-- and what stops a new one from needing eighteen numbers to be right. Any
-- derived key can still be pinned by naming it in the spec.
--
-- Nothing here is player-visible: display names are localized, keyed on `id`
-- (options.themeName.<id>).
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
        accent    = { 0.25, 0.25, 0.25 }, -- focus, fills, glow
        accentAlt = { 0.9, 0.9, 0.9 }, -- violet partner for gradients and gas
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

local palettes = {}    -- id -> resolved flat color table
local paletteList = {} -- { { id = ... }, ... }, in PALETTES order

for _, spec in ipairs(PALETTES) do
    palettes[spec.id] = buildPalette(spec)
    paletteList[#paletteList + 1] = { id = spec.id }
end

Theme.current = Theme.DEFAULT

-- Copies a resolved palette into Theme.colors *in place*. Widgets, particle
-- layers and the wordmark's gradient all hold references to the individual
-- color tables, so a theme switch has to rewrite the numbers inside them rather
-- than hand out new tables — same reason Theme.rescale mutates Theme.metrics.
-- The fourth slot is written unconditionally so a palette without an alpha
-- clears one left by the palette before it.
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

-- Available themes for a selector: { {id="default"}, ... }, in the order they're
-- declared above. The same table every call — it's derived from a constant.
function Theme.available()
    return paletteList
end

-- Switches the active palette. Unknown ids fall back to the default, so a saved
-- theme from a build that offered more of them can never leave the UI colorless.
-- Returns true when the palette actually changed, so callers can skip the work
-- that a switch forces (the nebula's gas is baked with the accent burnt into it
-- and has to be re-baked; everything else re-reads Theme.colors as it draws).
function Theme.setTheme(id)
    if not palettes[id] then id = Theme.DEFAULT end
    if id == Theme.current then return false end

    Theme.current = id
    applyPalette(palettes[id])
    -- The clear color is GL state rather than something read per frame, so it
    -- has to be pushed again every time bg moves.
    love.graphics.setBackgroundColor(Theme.colors.bg)
    return true
end

-- The wordmark's gradient stops, as the live color tables (see gameTitle.lua).
-- Always exactly three, in every palette: TextFactory bakes the stop *count*
-- into the shader at build time but re-reads the colors every draw, so holding
-- the count fixed is what lets a theme switch recolor the title with no rebuild.
function Theme.titleGradient()
    return { Theme.colors.titleGradient1, Theme.colors.titleGradient2, Theme.colors.titleGradient3 }
end

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
-- text sitting right under it. `family` is optional and looked up in
-- FONT_FAMILIES above; a role that omits it gets DEFAULT_FAMILY, which is why
-- every role below can leave it out today without changing anything.
local fontRoles = {
    title = { file = "Orbitron-ExtraBold.ttf", family = "orbitron", size = 72 }, -- game title
    title2 = { file = "Acme9_TITLE.ttf", family = "acme", size = 55  }, -- game title, alternate.
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
        local dir = FONT_FAMILIES[role.family or DEFAULT_FAMILY]
        assert(dir, "Theme.font: role '" .. name .. "' names unknown family '" .. tostring(role.family) .. "'")
        -- Fall back to LÖVE's default font if the .ttf can't be opened, so a
        -- missing/renamed font file degrades gracefully instead of crashing
        -- (also lets headless tests run without the assets dir mounted).
        local ok, font = pcall(love.graphics.newFont, dir .. role.file, size)
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

-- The colors a row moves through as it lights up: the border it rests at, the
-- border and glow it reaches when focused or hovered, and the fill underneath.
-- Named by key rather than holding the color tables, so this stays a plain
-- constant that a theme switch — which rewrites Theme.colors in place — has
-- nothing to invalidate.
local TONES = {
    accent = { rest = "panelBorder",  lit = "accent", fill = "accentDark" },
    danger = { rest = "dangerBorder", lit = "danger", fill = "dangerDark" },
}

-- The standard interactive-row background, shared by button/toggle/slider/
-- selector: a pulsing glow halo when focused, a fill easing panel -> the tone's
-- dark with focus, and a border easing the tone's resting color -> its lit one.
-- `glow` is the widget's eased 0..1 focus amount, `time` drives the halo pulse.
-- `alpha` (default 1) fades only the border for disabled rows, matching the
-- Selector's greyed look (the fill stays opaque so the row still reads as a
-- solid control).
--
-- `tone` picks which color set to light up in: "accent" (the default) or
-- "danger" for a row that destroys something. A danger row is red-leaning even
-- at rest and goes fully red under the cursor, so the difference registers
-- before the label has been read — see Widget's `danger` flag.
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

-- Standard panel: filled rounded rect with a border.
function Theme.panel(x, y, w, h)
    local radius = Theme.metrics.radius
    love.graphics.setColor(Theme.colors.panel)
    love.graphics.rectangle("fill", x, y, w, h, radius, radius, 8)
    love.graphics.setColor(Theme.colors.panelBorder)
    love.graphics.rectangle("line", x, y, w, h, radius, radius, 8)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Seed colors and metrics so neither table is ever empty if something reads one
-- before love.load gets a chance to call setTheme/rescale. Seeded through
-- applyPalette rather than setTheme because this runs at require time, which is
-- too early to be touching love.graphics state.
applyPalette(palettes[Theme.DEFAULT])
Theme.rescale(DESIGN_HEIGHT)

return Theme
