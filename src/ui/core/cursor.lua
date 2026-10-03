--- The game's own mouse cursor: a pixel-art pointer in the menus, a dot during
-- gameplay. Screens describe it one frame at a time (setHover, setPosition,
-- useGameCursor) and draw() forgets all three, so a screen that stops asking,
-- or stops existing, hands the cursor back with no teardown to forget.

local Math = require("utils.math")
local Motion = require("ui.core.motion")
local Theme = require("ui.core.theme")
local Tint = require("ui.shaders.tint")

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

-- settings
local enabled = true
local size = DEFAULT_SIZE
local restOutlineWidth = DEFAULT_OUTLINE_WIDTH
local hoverOutlineWidth = DEFAULT_HOVER_OUTLINE_WIDTH
local clickGrowth = DEFAULT_CLICK_GROWTH
local pointerColor = pointerColors.theme

-- this frame's requests, cleared by draw()
local hovering = false
local danger = false
local pinnedX, pinnedY = nil, nil
local gameCursor = false

-- eased state
local function copyRGB(color) return { color[1], color[2], color[3] } end
local current = copyRGB(Theme.colors.cursor)
local currentOutline = copyRGB(Theme.colors.shadow)
local outlineWidth = restOutlineWidth
local click = nil -- seconds since the last press, while its ring is still showing

local textures = {} -- file -> { image, peakLuma }, or false if it failed to load

---@param file string
---@return table|false # { image = love.Image, peakLuma = number }, or false when it couldn't be loaded
local function getTexture(file)
    if textures[file] == nil then
        local path = TEXTURE_DIR .. file
        local ok, result = pcall(function()
            local data = love.image.newImageData(path)
            local image = love.graphics.newImage(data)
            image:setFilter("nearest", "nearest")
            return { image = image, peakLuma = Tint.peakLuma(data) }
        end)
        if not ok then print("[cursor] failed to load " .. path .. ": " .. tostring(result)) end
        textures[file] = ok and result
    end
    return textures[file]
end

---@param color number[] # eased in place
---@param target number[]
---@param dt number
local function approachColor(color, target, dt)
    color[1] = Theme.approach(color[1], target[1], dt)
    color[2] = Theme.approach(color[2], target[2], dt)
    color[3] = Theme.approach(color[3], target[3], dt)
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
    if not enabled then click = nil end
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
    size = math.max(0, value)
end

--- design-space line width at rest; the options.customCursorOutlineWidth setting
---@param value number
function Cursor.setOutlineWidth(value)
    restOutlineWidth = math.max(0, value)
end

--- design-space line width while hovering something interactive; the
-- options.customCursorHoverOutlineWidth setting
---@param value number
function Cursor.setHoverOutlineWidth(value)
    hoverOutlineWidth = math.max(0, value)
end

--- how far past the radius the click ring expands, design-space; the
-- options.customCursorClickGrowth setting
---@param value number
function Cursor.setClickGrowth(value)
    clickGrowth = math.max(0, value)
end

--- for this frame: the pointer is over something interactive. Call it before
-- Cursor.update; not calling it is how a screen says "nothing", so the cursor
-- eases back to rest on its own.
---@param isHovering boolean
---@param isDanger? boolean # draws the danger colour rather than the accent
function Cursor.setHover(isHovering, isDanger)
    hovering = isHovering
    danger = isHovering and isDanger or false
end

--- for this frame: draw the cursor somewhere other than the OS pointer -- the
-- play screen tethers it inside the player's reach
---@param x number # screen space
---@param y number # screen space
function Cursor.setPosition(x, y)
    pinnedX, pinnedY = x, y
end

--- for this frame: swap the menus' pixel-art pointer for the in-game dot (the
-- one the customCursor* settings tune)
function Cursor.useGameCursor()
    gameCursor = true
end

--- starts the click ring; forward love.mousepressed here. An event rather than
-- polling isDown, so a press and release inside one frame still shows.
---@param button number
function Cursor.mousepressed(_, _, button)
    if button == 1 and enabled and not Motion.reduced then click = 0 end
end

--- eases colour and outline toward whatever setHover asked for this frame,
-- and ages the click ring
---@param dt number
function Cursor.update(dt)
    local c = Theme.colors
    local target = c.cursor
    if hovering then
        target = danger and c.danger or c.accent
    end
    approachColor(current, target, dt)
    approachColor(currentOutline, hovering and c.highlight or c.shadow, dt)
    outlineWidth = Theme.approach(outlineWidth, hovering and hoverOutlineWidth or restOutlineWidth, dt)

    if click and Motion.reduced then click = nil end
    if click then
        click = click + dt
        if click >= CLICK_LIFE then click = nil end
    end
end

---@param x number
---@param y number
---@param hover boolean
---@return boolean # false when the art didn't load, so the caller draws the dot instead
local function drawPointer(x, y, hover)
    local pointer = hover and POINTERS.select or POINTERS.rest
    local texture = getTexture(pointer.file)
    if not texture and pointer ~= POINTERS.rest then
        pointer = POINTERS.rest
        texture = getTexture(pointer.file)
    end
    if not texture then return false end

    local shader = pointerColor.id ~= "original" and Tint.get()
    if shader then
        shader:send("peakLuma", texture.peakLuma)
        love.graphics.setShader(shader)
        local rgb = pointerColor.rgb or current
        love.graphics.setColor(rgb[1], rgb[2], rgb[3], 1)
    else
        love.graphics.setColor(1, 1, 1, 1)
    end
    local scale = math.max(1, Theme.px(POINTER_SCALE))
    love.graphics.draw(texture.image, Math.round(x), Math.round(y), 0,
        scale, scale, pointer.hotX, pointer.hotY)
    return true
end

---@param x number
---@param y number
local function drawDot(x, y)
    local radius = Theme.px(size)

    if click then
        local t = click / CLICK_LIFE
        Theme.setColor(current, 1 - t)
        love.graphics.setLineWidth(math.max(1, Theme.px(restOutlineWidth)))
        love.graphics.circle("line", x, y, radius + Theme.px(clickGrowth) * t, 16)
    end

    Theme.setColor(current, 1)
    love.graphics.circle("fill", x, y, radius, 6)

    Theme.setColor(currentOutline)
    love.graphics.setLineWidth(math.max(1, Theme.px(outlineWidth)))
    love.graphics.circle("line", x, y, radius, 32)
end

--- at the OS pointer, or wherever setPosition pinned it this frame: the dot
-- during gameplay, the pixel-art pointer everywhere else. Draw it last, after
-- everything else in love.draw.
function Cursor.draw()
    local x, y = pinnedX, pinnedY
    local game, hover = gameCursor, hovering
    -- cleared even when disabled, so nothing goes stale
    pinnedX, pinnedY, gameCursor, hovering, danger = nil, nil, false, false, false

    if not enabled then return end
    if not (x and y) then
        -- left at the window's edge, it would look like a stuck OS cursor
        if not love.window.hasMouseFocus() then return end
        x, y = love.mouse.getPosition()
    end

    -- screen space, whatever transform the frame left behind, and every bit
    -- of state it borrows handed back afterwards
    love.graphics.push("all")
    love.graphics.origin()
    if game or not drawPointer(x, y, hover) then
        drawDot(x, y)
    end
    love.graphics.pop()
end

return Cursor
