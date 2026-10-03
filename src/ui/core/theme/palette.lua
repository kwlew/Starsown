--- Turns one palettes.lua spec into the full set of roles the UI draws with.
-- Owns the shared neutrals and every derivation constant; holds no state.

local Color = require("utils.math").Color

local blend, normalized, tinted = Color.blend, Color.normalized, Color.tinted

local Palette = {}

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
---@param spec table # a palettes.lua entry
---@return table<string, number[]> colors
function Palette.build(spec)
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

return Palette
