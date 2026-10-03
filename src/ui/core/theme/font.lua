--- Font roles, the interface font family a player picked, and the cache of
-- built love.Fonts at the current UI scale.

local Math = require("utils.math")
local Metrics = require("ui.core.theme.metrics")

local Font = {}

local FONT_FAMILIES = {
    acme = "assets/fonts/Acme/",
    oxanium  = "assets/fonts/Oxanium/",
    orbitron = "assets/fonts/Orbitron/static/",
    jetmono  = "assets/fonts/JetMono/",
    play     = "assets/fonts/Play/",
}
local DEFAULT_FAMILY = "oxanium"

local fontRoles = {
    title = { file = "Orbitron-ExtraBold.ttf", family = "orbitron", size = 80 },
    title2 = { file = "Acme9_TITLE.ttf", family = "acme", size = 52 },
    title3 = { file = "JetBrainsMono-ExtraBold.ttf", family = "jetmono", size = 60 },
    heading = { size = 40 },
    button  = { size = 26 },
    body    = { size = 26 },
    help    = { size = 18 },
    small   = { size = 15 },
    debug   = { size = 14 },
}

local UI_FONT_FAMILIES = {
    {
        id      = "oxanium",
        heading = { file = "Oxanium-Bold.ttf",     fallback = "Play-Bold.ttf" },
        button  = { file = "Oxanium-SemiBold.ttf", fallback = "Play-Bold.ttf" },
        body    = { file = "Oxanium-Medium.ttf",   fallback = "Play-Regular.ttf" },
        help    = { file = "Oxanium-Regular.ttf",  fallback = "Play-Regular.ttf" },
        small   = { file = "Oxanium-Regular.ttf",  fallback = "Play-Regular.ttf" },
        debug   = { file = "Oxanium-Medium.ttf",   fallback = "Play-Regular.ttf" },
    },
    {
        id      = "jetmono",
        heading = { file = "JetBrainsMono-Regular.ttf", size = 31 },
        button  = { file = "JetBrainsMono-Regular.ttf", size = 20 },
        body    = { file = "JetBrainsMono-Regular.ttf", size = 20 },
        help    = { file = "JetBrainsMono-Regular.ttf", size = 14 },
        small   = { file = "JetBrainsMono-Regular.ttf", size = 12 },
        debug   = { file = "JetBrainsMono-Regular.ttf", size = 11 },
    },
}

local uiFontFamilies = {}
for _, spec in ipairs(UI_FONT_FAMILIES) do uiFontFamilies[spec.id] = spec end

Font.DEFAULT_UI_FONT = UI_FONT_FAMILIES[1].id
local uiFont = Font.DEFAULT_UI_FONT

local fontCache = {}
local capHeights = setmetatable({}, { __mode = "k" }) -- font -> px a capital rises above the baseline
local fontStack = {}

---@param name string
---@return table # a buildFont-ready { file, family, fallback?, size }
local function resolveRole(name)
    local base = fontRoles[name]
    local override = uiFontFamilies[uiFont][name]
    if not override then return base end
    return {
        size = override.size or base.size,
        family = uiFont, file = override.file, fallback = override.fallback,
    }
end

---@param path string|nil # nil for LÖVE's built-in font
---@param size integer
---@return number|nil
local function measureCapHeight(path, size)
    local ok, height = pcall(function()
        local rasterizer = path and love.font.newRasterizer(path, size) or love.font.newRasterizer(size)
        local _, bearingY = rasterizer:getGlyphData("H"):getBearing()
        return bearingY
    end)
    return ok and height or nil
end

--- build font or revert to LOVE2D default.
---@param name string # role name, for the assert message
---@param role table # a resolved fontRoles entry
---@param size integer # already scaled to screen pixels
---@return any # a love.Font
local function buildFont(name, role, size)
    local dir = FONT_FAMILIES[role.family or DEFAULT_FAMILY]
    assert(dir, "Theme: role '" .. name .. "' names unknown family '" .. tostring(role.family) .. "'")

    local ok, font = pcall(love.graphics.newFont, dir .. role.file, size)
    font = ok and font or love.graphics.newFont(size)
    capHeights[font] = measureCapHeight(ok and dir .. role.file or nil, size)

    if role.fallback then
        local fbOk, fallback = pcall(love.graphics.newFont, FONT_FAMILIES.play .. role.fallback, size)
        if fbOk then font:setFallbacks(fallback) end
    end

    return font
end

--- drops every built font; the next Font.get rebuilds at the current scale
function Font.clearCache()
    fontCache = {}
end

--- the cached font for a role, at the current UI scale
---@param name "title"|"title2"|"title3"|"heading"|"button"|"body"|"help"|"small"|"debug"|string
---@return any # a love.Font
function Font.get(name)
    local base = fontRoles[name]
    assert(base, "Theme.font: unknown font '" .. tostring(name) .. "'")
    if not fontCache[name] then
        local size = math.max(1, Math.round(base.size * Metrics.scale))
        fontCache[name] = buildFont(name, resolveRole(name), size)
    end
    return fontCache[name]
end

---@param name string # a font role
---@param designSize number # design-space point size, at the base family's scale
---@return any # a love.Font; uncached
function Font.sized(name, designSize)
    local base = fontRoles[name]
    assert(base, "Theme.fontSized: unknown font '" .. tostring(name) .. "'")
    local resolved = resolveRole(name)
    local size = math.max(1, Math.round(designSize * (resolved.size / base.size) * Metrics.scale))
    return buildFont(name, resolved, size)
end

--- lets a widget option be a Font, a role name, or nil
---@param font any # a love.Font, a role name, or nil
---@param defaultRole string # used when font is nil
---@return any # a love.Font
function Font.resolve(font, defaultRole)
    if type(font) == "userdata" then return font end
    return Font.get(type(font) == "string" and font or defaultRole)
end

---@return string[] # every role name, sorted
function Font.roles()
    local names = {}
    for name in pairs(fontRoles) do names[#names + 1] = name end
    table.sort(names)
    return names
end

---@return table[] # { id: string }[]; every interface font family, in authored order
function Font.uiFamilies()
    local list = {}
    for _, spec in ipairs(UI_FONT_FAMILIES) do list[#list + 1] = { id = spec.id } end
    return list
end

---@return string
function Font.currentUiFamily()
    return uiFont
end

--- switches every non-title role to another family at once; unknown ids are ignored
---@param id string
---@return boolean # changed; false if that family was already active or unknown
function Font.setUiFamily(id)
    if id == uiFont or not uiFontFamilies[id] then return false end
    uiFont = id
    Font.clearCache()
    return true
end

---@param font any # a love.Font
---@return number # px a capital letter rises above the baseline
function Font.capHeight(font)
    return capHeights[font] or font:getBaseline() * 0.7 -- a typical ratio, for a font this module didn't build
end

--- Centres the capitals, not the line box: getHeight() includes room below
-- the baseline for descenders, so centring that sat every label a few px
-- high -- invisible until an icon sat beside one.
---@param y number # row top
---@param h number # row height
---@param font any # a love.Font
---@return number # the y to draw one line of that font at
function Font.centerY(y, h, font)
    return Math.round(y + (h + Font.capHeight(font)) / 2 - font:getBaseline())
end

--- saves the active font and sets a new one; always pair with pop
---@param font any # a love.Font
function Font.push(font)
    fontStack[#fontStack + 1] = love.graphics.getFont()
    love.graphics.setFont(font)
end

--- restores the font the matching push saved
function Font.pop()
    local depth = #fontStack
    assert(depth > 0, "Theme.popFont: no matching pushFont")
    love.graphics.setFont(fontStack[depth])
    fontStack[depth] = nil
end

return Font
