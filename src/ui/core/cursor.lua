local Theme = require "ui.core.theme"
local Motion = require "ui.core.motion"

local Cursor = {}

local DEFAULT_SIZE = 3
local DEFAULT_OUTLINE_WIDTH = 0.5
local DEFAULT_HOVER_OUTLINE_WIDTH = 1
local DEFAULT_CLICK_GROWTH = 3

local CLICK_LIFE = 0.25

local TEXTURE_DIR = "assets/textures/game/"
-- hotspot: the art pixel that sits on the pointer (the arrow's tip, the finger's tip)
local POINTERS = {
    rest = { file = "cursor.png", hotX = 1, hotY = 0 },
    select = { file = "cursor_select.png", hotX = 3, hotY = 0 },
}
local POINTER_SCALE = 2 -- design-space multiple of the art, snapped to whole pixels

-- player-picked overrides for the pointer, so deliberately not theme roles.
-- "theme" follows the same colours as the dot; "original" draws the art as authored.
local POINTER_COLORS = {
    { id = "theme" },
    { id = "original" },
    { id = "white",  rgb = { 0.95, 0.95, 0.95 } },
    { id = "red",    rgb = { 0.92, 0.28, 0.28 } },
    { id = "orange", rgb = { 0.96, 0.58, 0.22 } },
    { id = "yellow", rgb = { 0.96, 0.84, 0.30 } },
    { id = "green",  rgb = { 0.38, 0.84, 0.44 } },
    { id = "cyan",   rgb = { 0.36, 0.86, 0.94 } },
    { id = "blue",   rgb = { 0.36, 0.56, 0.96 } },
    { id = "purple", rgb = { 0.66, 0.40, 0.95 } },
    { id = "pink",   rgb = { 0.96, 0.46, 0.72 } },
}
local pointerColors = {}
for _, entry in ipairs(POINTER_COLORS) do pointerColors[entry.id] = entry end

-- recolours the art as shades of one colour: each pixel's brightness, relative
-- to the art's brightest pixel, scales the tint, so outline and shading survive
local TINT_SHADER = [[
    uniform float peakLuma;
    vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
        vec4 texel = Texel(tex, uv);
        float luma = dot(texel.rgb, vec3(0.299, 0.587, 0.114)) / peakLuma;
        return vec4(min(color.rgb * luma, vec3(1.0)), texel.a * color.a);
    }
]]

local size = DEFAULT_SIZE
local restOutlineWidth = DEFAULT_OUTLINE_WIDTH
local hoverOutlineWidth = DEFAULT_HOVER_OUTLINE_WIDTH
local clickGrowth = DEFAULT_CLICK_GROWTH

local hovering = false
local danger = false
local current = { 1, 1, 1 }
local currentOutline = { Theme.colors.shadow[1], Theme.colors.shadow[2], Theme.colors.shadow[3] }
local enabled = true
local outlineWidth = restOutlineWidth
local wasDown = false
local click = nil
local pinnedX, pinnedY = nil, nil
local gameCursor = false
local pointerColor = pointerColors.theme
local textures = {} -- file -> { image, peakLuma }, or false if it failed to load
local tintShader -- nil until first needed, false if it failed to compile

---@param data any # love.ImageData
---@return number
local function peakLuma(data)
    local peak = 0
    data:mapPixel(function(_, _, r, g, b, a)
        if a > 0 then peak = math.max(peak, 0.299 * r + 0.587 * g + 0.114 * b) end
        return r, g, b, a
    end)
    return math.max(peak, 1 / 255)
end

---@param file string
---@return table|false # { image = love.Image, peakLuma = number }, or false when it couldn't be loaded
local function getTexture(file)
    if textures[file] == nil then
        local path = TEXTURE_DIR .. file
        local ok, result = pcall(function()
            local data = love.image.newImageData(path)
            local image = love.graphics.newImage(data)
            image:setFilter("nearest", "nearest")
            return { image = image, peakLuma = peakLuma(data) }
        end)
        if not ok then print("[ui] failed to load " .. path .. ": " .. tostring(result)) end
        textures[file] = ok and result
    end
    return textures[file]
end

---@return any # a love.Shader, or false when it couldn't be compiled
local function getTintShader()
    if tintShader == nil then
        local ok, shader = pcall(love.graphics.newShader, TINT_SHADER)
        if not ok then print("[ui] cursor tint shader failed: " .. tostring(shader)) end
        tintShader = ok and shader
    end
    return tintShader
end

--- draws our own cursor and hides the OS one; call once at boot
function Cursor.init()
    Cursor.setEnabled(true) 
end

--- the only place in this module that touches OS cursor visibility. Off shows
-- the OS arrow instead (the options.customCursor toggle).
---@param isEnabled boolean
function Cursor.setEnabled(isEnabled)
    enabled = isEnabled
    love.mouse.setVisible(not enabled)
end

---@return table[] # { id } entries, for the options.customCursorColor selector
function Cursor.pointerColors()
    return POINTER_COLORS
end

--- the pointer's colour: "theme", "original" or a preset id; the
-- options.customCursorColor setting. Unknown ids fall back to "theme".
---@param id string
function Cursor.setPointerColor(id)
    pointerColor = pointerColors[id] or pointerColors.theme
end

--- design-space radius (see Theme.px); the options.customCursorSize setting
---@param value number
function Cursor.setSize(value)
    size = value
end

--- design-space line width at rest; the options.customCursorOutlineWidth setting
---@param value number
function Cursor.setOutlineWidth(value)
    restOutlineWidth = value
end

--- design-space line width while hovering something interactive; the
-- options.customCursorHoverOutlineWidth setting
---@param value number
function Cursor.setHoverOutlineWidth(value)
    hoverOutlineWidth = value
end

--- how far past the radius the click ring expands, design-space; the
-- options.customCursorClickGrowth setting
---@param value number
function Cursor.setClickGrowth(value)
    clickGrowth = value
end

--- recoloured per frame by whatever the pointer is over; nothing calls this to
-- clear, so a screen that stops asserting hover fades back to rest on its own
---@param isHovering boolean
---@param isDanger? boolean # draws the danger colour rather than the accent
function Cursor.setHover(isHovering, isDanger)
    hovering = isHovering
    danger = isDanger or false
end

--- Draws the cursor somewhere other than the OS pointer for one frame -- the
-- play screen tethers it inside the player's reach. It lasts a single draw and
-- whoever wants it re-asserts every frame, so a screen that stops asking (or
-- stops existing) hands the pointer back with no teardown to forget.
---@param x number # screen space
---@param y number # screen space
function Cursor.setPosition(x, y)
    pinnedX, pinnedY = x, y
end

--- Swaps the menus' pixel-art pointer for the in-game dot (the one the
-- customCursor* settings tune) for one frame. Re-asserted every frame like
-- setPosition, so leaving gameplay brings the pointer back on its own.
function Cursor.useGameCursor()
    gameCursor = true
end

--- eases colour and outline toward whatever setHover last asked for, and runs
-- the click ring (suppressed under reduced motion)
---@param dt number
function Cursor.update(dt)
    local target = Theme.colors.cursor
    if hovering then
        target = danger and Theme.colors.danger or Theme.colors.accent
    end
    current[1] = Theme.approach(current[1], target[1], dt)
    current[2] = Theme.approach(current[2], target[2], dt)
    current[3] = Theme.approach(current[3], target[3], dt)

    local outlineTarget = hovering and Theme.colors.highlight or Theme.colors.shadow
    currentOutline[1] = Theme.approach(currentOutline[1], outlineTarget[1], dt)
    currentOutline[2] = Theme.approach(currentOutline[2], outlineTarget[2], dt)
    currentOutline[3] = Theme.approach(currentOutline[3], outlineTarget[3], dt)

    outlineWidth = Theme.approach(outlineWidth, hovering and hoverOutlineWidth or restOutlineWidth, dt)

    local isDown = enabled and love.mouse.isDown(1)
    if isDown and not wasDown and not Motion.reduced then click = 0 end
    wasDown = isDown
    if click then
        click = click + dt
        if click >= CLICK_LIFE then click = nil end
    end
end

---@param x number
---@param y number
---@return boolean # false when the art didn't load, so the caller draws the dot instead
local function drawPointer(x, y)
    local pointer = hovering and POINTERS.select or POINTERS.rest
    local texture = getTexture(pointer.file)
    if not texture and pointer ~= POINTERS.rest then
        pointer = POINTERS.rest
        texture = getTexture(pointer.file)
    end
    if not texture then return false end

    local shader = pointerColor.id ~= "original" and getTintShader()
    if shader then
        shader:send("peakLuma", texture.peakLuma)
        love.graphics.setShader(shader)
        local rgb = pointerColor.rgb or current
        love.graphics.setColor(rgb[1], rgb[2], rgb[3], 1)
    else
        love.graphics.setColor(1, 1, 1, 1)
    end
    local scale = math.max(1, math.floor(Theme.px(POINTER_SCALE) + 0.5))
    love.graphics.draw(texture.image, math.floor(x + 0.5), math.floor(y + 0.5), 0,
        scale, scale, pointer.hotX, pointer.hotY)
    love.graphics.setShader()
    love.graphics.setColor(1, 1, 1, 1)
    return true
end

--- at the OS pointer, or wherever setPosition pinned it this frame: the dot
-- during gameplay, the pixel-art pointer everywhere else
function Cursor.draw()
    local x, y = pinnedX, pinnedY
    local game = gameCursor
    pinnedX, pinnedY, gameCursor = nil, nil, false -- cleared even when disabled, so nothing goes stale
    if not enabled then return end
    if not x then x, y = love.mouse.getPosition() end

    if not game and drawPointer(x, y) then return end

    local radius = Theme.px(size)

    if click then
        local t = click / CLICK_LIFE
        Theme.setColor(current, 1 - t)
        love.graphics.setLineWidth(math.max(1, Theme.px(restOutlineWidth)))
        love.graphics.circle("line", x, y, radius + Theme.px(clickGrowth) * t, 16)
    end

    love.graphics.setColor(current[1], current[2], current[3], 1)
    love.graphics.circle("fill", x, y, radius, 6)

    Theme.setColor(currentOutline)
    love.graphics.setLineWidth(math.max(1, Theme.px(outlineWidth)))
    love.graphics.circle("line", x, y, radius, 32)
    love.graphics.setLineWidth(1)

    love.graphics.setColor(1, 1, 1, 1)
end

return Cursor
