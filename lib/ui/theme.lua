-- lib/ui/theme.lua
-- The style contract for the whole game: every color, font, and metric the UI
-- uses lives here, so changing the game's look means editing this file only.
-- Widgets and states must never hardcode style values — ask the theme.

local Theme = {}

-- Optional .ttf/.otf path (e.g. "assets/fonts/YourFont.ttf"). When set, every
-- UI font is built from it, reskinning all text in one line. nil = LÖVE default.
Theme.fontPath = "assets/fonts/Oxanium/Oxanium-ExtraBold.ttf"

Theme.colors = {
    bg          = { 0.05, 0.05, 0.07 }, -- window clear color
    panel       = { 0.10, 0.11, 0.14 }, -- widget/panel background
    panelBorder = { 0.25, 0.28, 0.35 },
    track       = { 0.18, 0.18, 0.20 }, -- empty bar/slider track
    text        = { 0.92, 0.94, 0.98 },
    textDim     = { 0.55, 0.58, 0.65 }, -- hints, footers, debug overlay
    accent      = { 0.30, 0.70, 1.00 }, -- the neon blue: focus, fills, glow
    accentDark  = { 0.13, 0.30, 0.45 }, -- focused-widget background
    accentAlt   = { 0.62, 0.40, 1.00 }, -- violet partner for gradients
}

Theme.metrics = {
    radius     = 8,  -- corner radius for every rounded rect
    padding    = 14, -- inner padding of widgets/panels
    rowHeight  = 48, -- standard widget row height
    rowGap     = 14, -- vertical gap between stacked widgets
    glowLayers = 4,  -- additive rects stacked into a halo
    glowSpread = 4,  -- px each glow layer grows beyond the last
    glowAlpha  = 0.16,
    focusSpeed = 10, -- how fast widgets ease toward their focused look
}

-- Lazily built, cached fonts. Sizes are the game's whole type scale.
local fontSizes = { title = 72, heading = 40, body = 26, small = 15 }
local fontCache = {}

function Theme.font(name)
    assert(fontSizes[name], "Theme.font: unknown font '" .. tostring(name) .. "'")
    if not fontCache[name] then
        local size = fontSizes[name]
        -- Fall back to LÖVE's default font if the .ttf can't be opened, so a
        -- missing/renamed font file degrades gracefully instead of crashing
        -- (also lets headless tests run without the assets dir mounted).
        if Theme.fontPath then
            local ok, font = pcall(love.graphics.newFont, Theme.fontPath, size)
            fontCache[name] = ok and font or love.graphics.newFont(size)
        else
            fontCache[name] = love.graphics.newFont(size)
        end
    end
    return fontCache[name]
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
-- shared glow/knob/highlight animation). Returns the new value.
function Theme.approach(current, target, dt)
    return current + (target - current) * math.min(dt * Theme.metrics.focusSpeed, 1)
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

-- Runs fn with `font` active, restoring the previous font afterward — replaces
-- the getFont/setFont/restore boilerplate repeated in every widget draw.
function Theme.withFont(font, fn)
    local previous = love.graphics.getFont()
    love.graphics.setFont(font)
    fn()
    love.graphics.setFont(previous)
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

return Theme
