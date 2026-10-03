--- The live colour tables every widget reads, and switching between the
-- palettes that fill them.

local Palette = require("ui.core.theme.palette")
local PALETTES = require("ui.core.theme.palettes")

local Colors = {}

Colors.DEFAULT = "default"
Colors.current = nil

--- live roles; written in place on a switch, never replaced (see apply)
Colors.colors = {}

--- roles no palette recolours
Colors.fixed = {
    starPop = { 1, 0.5, 0.2 },
    gold = { 1, 0.82, 0.35 },
    goldFlare = { 1, 0.60, 0.12 },
}

local palettes = {}
local paletteList = {}

--- apply writes into the live color tables rather than replacing them,
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
    local palette = Palette.build(spec)
    if firstPalette then
        assertRoles(firstPalette, firstId, palette, spec.id)
    else
        firstId, firstPalette = spec.id, palette
    end
    palettes[spec.id] = palette
    paletteList[#paletteList + 1] = { id = spec.id }
end

--- writes into the live colour tables in place, since widgets hold references
-- to them -- swapping the table would leave every widget on the old theme
---@param palette table<string, number[]>
local function apply(palette)
    for name, color in pairs(palette) do
        local live = Colors.colors[name]
        if live then
            live[1], live[2], live[3], live[4] = color[1], color[2], color[3], color[4]
        else
            Colors.colors[name] = { color[1], color[2], color[3], color[4] }
        end
    end
end

---@return table[] # { id: string }[]; every palette, in authored order
function Colors.available()
    return paletteList
end

--- repaints the whole UI, falling back to the default for an unknown id
---@param id string
---@return boolean # changed; false if that theme was already active
function Colors.setTheme(id)
    if not palettes[id] then id = Colors.DEFAULT end
    if id == Colors.current then return false end

    Colors.current = id
    apply(palettes[id])
    if love and love.graphics then
        love.graphics.setBackgroundColor(Colors.colors.bg)
    end
    return true
end

---@return number[][] # the three stops the chroma title shader reads
function Colors.titleGradient()
    local c = Colors.colors
    return { c.titleGradient1, c.titleGradient2, c.titleGradient3 }
end

---@param color number[] # RGB, or RGBA
---@param alpha? number # overrides the colour's own fourth component
function Colors.set(color, alpha)
    love.graphics.setColor(color[1], color[2], color[3], alpha or color[4] or 1)
end

Colors.setTheme(Colors.DEFAULT)

return Colors
