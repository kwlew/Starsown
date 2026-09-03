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

--- perceived brightness; what tinted() preserves while it recolours
---@param r number
---@param g number
---@param b number
---@return number
local function luminance(r, g, b)
    return 0.30 * r + 0.59 * g + 0.11 * b
end

---@param a number
---@param b number
---@param t number # 0..1
---@return number # clamped to 0..1
local function mix(a, b, t)
    return Math.clamp01(a + (b - a) * t)
end

---@param a number[] RGB
---@param b number[] RGB
---@param t number # 0..1
---@return number[] RGB
local function blend(a, b, t)
    return { mix(a[1], b[1], t), mix(a[2], b[2], t), mix(a[3], b[3], t) }
end

--- the hue with its brightest channel pushed to 1, so a dark accent still
-- reads as its own colour when something tints toward it
---@param color number[] RGB
---@return number[] RGB
local function normalized(color)
    local peak = math.max(color[1], color[2], color[3])
    if peak <= 0 then return { 0, 0, 0 } end
    return { color[1] / peak, color[2] / peak, color[3] / peak }
end

--- pulls a neutral toward a hue while keeping its luminance, which is what
-- lets one set of greys serve every palette: a tinted panel stays as light or
-- dark as it was authored, only warmer or cooler
---@param base number[] # RGB, a NEUTRALS entry
---@param hue number[] # RGB to tint toward
---@param amount number # 0..1
---@return number[] RGB
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

--- one scalar, or per-role multipliers where `default` covers the rest
---@param tint any # a scalar, or a per-role table that may set `default` for the roles it doesn't name
---@return table<string, number> # role -> tint amount
local function tintAmounts(tint)
    local amounts = {}
    local perRole = type(tint) == "table"
    local fallback = perRole and (tint.default or 1) or (tint or 1)

    for name, base in pairs(TINT_STRENGTH) do
        amounts[name] = base * (perRole and (tint[name] or fallback) or fallback)
    end
    return amounts
end

--- derives every role the UI draws with from a handful of authored numbers.
-- Any role may be overridden outright by naming it in the spec.
---@param spec table # a PALETTES entry
---@return table<string, number[]> colors
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
        id        = "default",
        accent    = { 0.34, 0.68, 0.96 },
        accentAlt = { 0.62, 0.42, 0.98 },
        tint      = 0.70,
        title     = { { 0.25, 0.60, 1.00 }, { 0.85, 0.92, 1.00 }, { 0.62, 0.40, 1.00 } },
    },
    {
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
        id        = "amethyst",
        accent    = { 0.52, 0.18, 0.72 },
        accentAlt = { 0.82, 0.26, 0.66 },
        tint      = 0.75,
    },
    {
        id        = "emerald",
        accent    = { 0.30, 0.82, 0.56 },
        accentAlt = { 0.36, 0.76, 0.96 },
        tint      = 0.70,
        title     = { { 0.20, 0.90, 0.55 }, { 0.88, 1.00, 0.92 }, { 0.30, 0.78, 1.00 } },
    },
    {
        id        = "lavender",
        accent    = { 0.68, 0.38, 0.95 },
        accentAlt = { 0.95, 0.46, 0.82 },
        tint      = 0.75,
        title     = { { 0.62, 0.25, 1.00 }, { 0.95, 0.86, 1.00 }, { 1.00, 0.40, 0.85 } },
    },
    {
        id        = "topaz",
        accent    = { 0.95, 0.80, 0.32 },
        accentAlt = { 0.96, 0.52, 0.30 },
        tint      = { default = 0.70, text = 0.25, textMuted = 0.30, textDim = 0.40 },
        danger    = { 0.95, 0.10, 0.14 },
        title     = { { 1.00, 0.90, 0.30 }, { 1.00, 0.95, 0.82 }, { 1.00, 0.50, 0.30 } },
    },
    {
        id        = "ember",
        accent    = { 0.96, 0.58, 0.22 },
        accentAlt = { 0.96, 0.36, 0.44 },
        tint      = 0.70,
        warning   = { 1.00, 0.88, 0.48 },
        danger    = { 1.00, 0.26, 0.30 },
        title     = { { 1.00, 0.72, 0.25 }, { 1.00, 0.95, 0.82 }, { 1.00, 0.38, 0.32 } },
    },
    {
        id        = "slate",
        accent    = { 0.70, 0.78, 0.92 },
        accentAlt = { 0.52, 0.60, 0.76 },
        tint      = 0.40,
    },
    {
        id        = "ruby",
        accent    = { 0.80, 0.18, 0.20 },
        accentAlt = { 0.96, 0.52, 0.32 },
        tint      = 0.5,
        danger    = { 0.98, 0.32, 0.30 },
        title     = { { 0.75, 0.10, 0.10 }, { 1.00, 0.90, 0.85 }, { 0.75, 0.20, 0.10 } },
    },
    {
        id        = "diamond",
        accent    = { 0.45, 0.86, 0.94 },
        accentAlt = { 0.68, 0.94, 1.00 },
        tint      = 0.45,
    },
    {
        id        = "lapis",
        accent    = { 0.30, 0.48, 0.92 },
        accentAlt = { 0.42, 0.70, 1.00 },
        tint      = 0.45,
    },
    {
        id        = "rose",
        accent    = { 0.76, 0.22, 0.44 },
        accentAlt = { 0.62, 0.30, 0.80 },
        tint      = 0.45,
    },
}

Theme.DEFAULT = "default"

local palettes = {}
local paletteList = {}

--- applyPalette writes into the live color tables rather than replacing them,
-- so a role missing from one palette keeps the outgoing theme's value after a
-- switch. A typo'd override is how that happens; catch it at load instead.
---@param reference table # the first palette built, used as the role set
---@param referenceId string
---@param palette table
---@param id string
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

--- writes into the live colour tables in place, since widgets hold references
-- to them -- swapping the table would leave every widget on the old theme
---@param palette table<string, number[]>
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

---@return table[] # { id: string }[]; every palette, in authored order
function Theme.available()
    return paletteList
end

--- repaints the whole UI, falling back to the default for an unknown id
---@param id string
---@return boolean # changed; false if that theme was already active
function Theme.setTheme(id)
    if not palettes[id] then id = Theme.DEFAULT end
    if id == Theme.current then return false end

    Theme.current = id
    applyPalette(palettes[id])
    love.graphics.setBackgroundColor(Theme.colors.bg) 
    return true
end

---@return number[][] # the three stops the chroma title shader reads
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
local glowCache = {}
local glowCacheCount = 0
local MAX_GLOW_CACHE = 16

--- snapped to SCALE_STEP so a slow window drag doesn't rebuild fonts every pixel
---@param height number # window height in pixels
---@return number
local function scaleForHeight(height)
    local s = Math.clamp(height / DESIGN_HEIGHT, SCALE_MIN, SCALE_MAX)
    return Math.round(s / SCALE_STEP) * SCALE_STEP
end

--- recomputes the UI scale and metrics for a window height, dropping the font
-- and glow caches when it actually changed. Call on resize.
---@param height? number # defaults to the current window height
---@return boolean changed
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
    glowCache = {}
    glowCacheCount = 0
    return true
end

--- design space (authored against a 720p height) to screen pixels; every
-- literal pixel constant in the project goes through here before it's drawn
---@param value number
---@return integer
function Theme.px(value)
    return Math.round(value * Theme.scale)
end

--- best-effort: a missing font file degrades to LÖVE's default rather than
-- crashing, and the Cyrillic fallback is attached only if it loads too
---@param name string # role name, for the assert message
---@param role table # a fontRoles entry
---@param size integer # already scaled to screen pixels
---@return any # a love.Font
local function buildFont(name, role, size)
    local dir = FONT_FAMILIES[role.family or DEFAULT_FAMILY]
    assert(dir, "Theme: role '" .. name .. "' names unknown family '" .. tostring(role.family) .. "'")

    local ok, font = pcall(love.graphics.newFont, dir .. role.file, size)
    font = ok and font or love.graphics.newFont(size)

    if role.fallback then
        local fbOk, fallback = pcall(love.graphics.newFont, FONT_FAMILIES.play .. role.fallback, size)
        if fbOk then font:setFallbacks(fallback) end
    end

    return font
end

--- the cached font for a role, at the current UI scale
---@param name "title"|"title2"|"heading"|"button"|"body"|"small"|"debug"|string
---@return any # a love.Font
function Theme.font(name)
    local role = fontRoles[name]
    assert(role, "Theme.font: unknown font '" .. tostring(name) .. "'")
    if not fontCache[name] then
        local size = math.max(1, Math.round(role.size * Theme.scale))
        fontCache[name] = buildFont(name, role, size)
    end
    return fontCache[name]
end

--- like Theme.font, but rasterized at an explicit design-space size instead
-- of the role's own, and not cached -- for a one-off larger/smaller render
-- of an existing typeface (e.g. loading screen's big version label, same
-- face as "small") that a caller will itself scale down toward, never up
---@param name string # a font role
---@param designSize number # design-space point size
---@return any # a love.Font; uncached
function Theme.fontSized(name, designSize)
    local role = fontRoles[name]
    assert(role, "Theme.fontSized: unknown font '" .. tostring(name) .. "'")
    local size = math.max(1, Math.round(designSize * Theme.scale))
    return buildFont(name, role, size)
end

---@return string[] # every role name, sorted
function Theme.fontRoles()
    local names = {}
    for name in pairs(fontRoles) do names[#names + 1] = name end
    table.sort(names)
    return names
end

--- lets a widget option be a Font, a role name, or nil
---@param font any # a love.Font, a role name, or nil
---@param defaultRole string # used when font is nil
---@return any # a love.Font
function Theme.fontFor(font, defaultRole)
    if type(font) == "userdata" then return font end
    return Theme.font(type(font) == "string" and font or defaultRole)
end

---@param color number[] # RGB, or RGBA
---@param alpha? number # overrides the colour's own fourth component
function Theme.setColor(color, alpha)
    love.graphics.setColor(color[1], color[2], color[3], alpha or color[4] or 1)
end

---@param a number[] RGB
---@param b number[] RGB
---@param t number # 0..1
---@return number r
---@return number g
---@return number b
function Theme.lerp(a, b, t)
    return a[1] + (b[1] - a[1]) * t,
           a[2] + (b[2] - a[2]) * t,
           a[3] + (b[3] - a[3]) * t
end

---@param px number
---@param py number
---@param x number
---@param y number
---@param w number
---@param h number
---@return boolean
function Theme.pointIn(px, py, x, y, w, h)
    return px >= x and px <= x + w and py >= y and py <= y + h
end

--- linear, dt-clamped easing toward a moving target -- the UI's standard
-- "chase this value". utils/math.lua's damp() is the exponential version.
---@param current number
---@param target number
---@param dt number
---@param speed? number # defaults to the theme's focusSpeed
---@return number
function Theme.approach(current, target, dt, speed)
    return current + (target - current) * math.min(dt * (speed or Theme.metrics.focusSpeed), 1)
end

---@param time number seconds
---@return number # 0.5..1, the shared breathing multiplier for glows
function Theme.pulse(time)
    return 0.75 + 0.25 * math.sin(time * 3)
end

---@param y number # row top
---@param h number # row height
---@param font any # a love.Font
---@return number # the y that centres one line of that font in the row
function Theme.centerY(y, h, font)
    return y + (h - font:getHeight()) / 2
end

local fontStack = {}

--- saves the active font and sets a new one; always pair with popFont
---@param font any # a love.Font
function Theme.pushFont(font)
    fontStack[#fontStack + 1] = love.graphics.getFont()
    love.graphics.setFont(font)
end

--- restores the font the matching pushFont saved
function Theme.popFont()
    local depth = #fontStack
    assert(depth > 0, "Theme.popFont: no matching pushFont")
    love.graphics.setFont(fontStack[depth])
    fontStack[depth] = nil
end

--- a label may be a string or a function of its widget, so a control whose
-- text depends on its own value (a toggle, a selector) needs no refresh call
---@param label? string|fun(owner: table): string
---@param owner table # passed to a function label
---@return string
function Theme.resolveLabel(label, owner)
    if type(label) == "function" then
        return label(owner)
    end
    return label or ""
end

--- bakes the layered glow for one rectangle size into a canvas, restoring
-- every piece of graphics state it borrows
---@param w number
---@param h number
---@param radius number # corner radius
---@return table # { canvas: love.Canvas, pad: number }
local function buildGlow(w, h, radius)
    local m = Theme.metrics
    local pad = m.glowLayers * m.glowSpread
    local canvas = love.graphics.newCanvas(math.ceil(w + pad * 2), math.ceil(h + pad * 2))
    canvas:setFilter("linear", "linear")

    local previousCanvas = love.graphics.getCanvas()
    local previousBlend, previousAlphaMode = love.graphics.getBlendMode()
    local previousR, previousG, previousB, previousA = love.graphics.getColor()
    local previousShader = love.graphics.getShader()

    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.push()
    love.graphics.origin()
    love.graphics.setShader()
    love.graphics.setBlendMode("add", "premultiplied")
    for i = m.glowLayers, 1, -1 do
        local spread = i * m.glowSpread
        local weight = m.glowAlpha / i
        love.graphics.setColor(weight, weight, weight, weight)
        love.graphics.rectangle("fill",
            pad - spread, pad - spread,
            w + spread * 2, h + spread * 2,
            radius + spread, radius + spread)
    end
    love.graphics.pop()

    love.graphics.setCanvas(previousCanvas)
    love.graphics.setBlendMode(previousBlend, previousAlphaMode)
    love.graphics.setColor(previousR, previousG, previousB, previousA)
    love.graphics.setShader(previousShader)
    return { canvas = canvas, pad = pad }
end

--- cached by size; the whole cache is dropped once it outgrows MAX_GLOW_CACHE
-- rather than evicting one entry, since these are only rebuilt on resize or a
-- new control size appearing
---@param w number
---@param h number
---@param radius number
---@return table # { canvas: love.Canvas, pad: number }
local function getGlow(w, h, radius)
    local byHeight = glowCache[w]
    if not byHeight then
        byHeight = {}
        glowCache[w] = byHeight
    end
    local byRadius = byHeight[h]
    if not byRadius then
        byRadius = {}
        byHeight[h] = byRadius
    end
    local glow = byRadius[radius]
    if not glow then
        if glowCacheCount >= MAX_GLOW_CACHE then
            glowCache = {}
            glowCacheCount = 0
            byHeight = {}
            byRadius = {}
            glowCache[w] = byHeight
            byHeight[h] = byRadius
        end
        glow = buildGlow(w, h, radius)
        byRadius[radius] = glow
        glowCacheCount = glowCacheCount + 1
    end
    return glow
end

--- a layered additive glow around a rounded rectangle
---@param x number
---@param y number
---@param w number
---@param h number
---@param radius number # corner radius
---@param intensity number # 0..1
---@param color? number[] # RGB, defaults to the theme's glow role
---@param cached? boolean # bake the layers to a canvas; only for geometry that repeats at a stable size
function Theme.glowRect(x, y, w, h, radius, intensity, color, cached)
    color = color or Theme.colors.glow
    if not cached then
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
        return
    end

    local glow = getGlow(w, h, radius)
    local r, g, b = color[1] * intensity, color[2] * intensity, color[3] * intensity

    love.graphics.setBlendMode("add", "premultiplied")
    love.graphics.setColor(r, g, b, 1)
    love.graphics.draw(glow.canvas, x - glow.pad, y - glow.pad)
    love.graphics.setBlendMode("alpha")
end

local TONES = {
    accent = { rest = "panelBorder",  lit = "accent", fill = "accentDark", glow = "glow" },
    danger = { rest = "dangerBorder", lit = "danger", fill = "dangerDark", glow = "danger" },
}

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
function Theme.rowChrome(x, y, w, h, glow, time, alpha, tone)
    alpha = alpha or 1
    local c, m = Theme.colors, Theme.metrics
    local set = TONES[tone] or TONES.accent
    local lit = c[set.lit]

    if glow > 0.01 then
        Theme.glowRect(x, y, w, h, m.radius, glow * Theme.pulse(time), c[set.glow], true)
    end
    love.graphics.setColor(Theme.lerp(c.panel, c[set.fill], glow))
    love.graphics.rectangle("fill", x, y, w, h, m.radius, m.radius, 10)
    local br, bg, bb = Theme.lerp(c[set.rest], lit, glow)
    love.graphics.setColor(br, bg, bb, alpha)
    love.graphics.rectangle("line", x, y, w, h, m.radius, m.radius, 10)
end

--- a filled, bordered surface at the theme's corner radius
---@param x number
---@param y number
---@param w number
---@param h number
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
