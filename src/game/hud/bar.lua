--- One HUD row: a pixel-art icon and a bordered bar.

local Math = require("utils.math")
local Textures = require("game.textures")
local UI = require("ui")

local Bar = {}

local ICON_DIR = "assets/textures/game/ui/"
Bar.ICON_SIZE = 32 -- 16px art at 2x on 720p
Bar.WIDTH = 200
local GAP = 8
local BORDER = 2
local SHADOW = 2 -- design px drop, so it reads over the ground without a panel

---@param fill number # 0..1
---@param color number[]
local function drawBar(fill, x, y, w, h, color)
    local Theme, c = UI.Theme, UI.Theme.colors
    local border = math.max(1, Theme.px(BORDER))
    local drop = Theme.px(SHADOW)
    Theme.setColor(c.shadow)
    love.graphics.rectangle("fill", x + drop, y + drop, w, h)
    Theme.setColor(c.panelBorder)
    love.graphics.rectangle("fill", x, y, w, h)
    Theme.setColor(c.track)
    love.graphics.rectangle("fill", x + border, y + border, w - border * 2, h - border * 2)
    if fill > 0 then
        Theme.setColor(color)
        love.graphics.rectangle("fill", x + border, y + border, Math.round((w - border * 2) * fill), h - border * 2)
    end
end

---@param name string
---@param size number # screen px box
local function drawIcon(name, x, y, size)
    local image = Textures.get(ICON_DIR .. name .. ".png")
    if not image then return end
    local w, h = image:getDimensions()
    local scale = math.max(1, Math.round(size / w))
    local ix, iy = x + Math.round((size - w * scale) / 2), y + Math.round((size - h * scale) / 2)
    local drop = UI.Theme.px(SHADOW)
    UI.Theme.setColor(UI.Theme.colors.shadow)
    love.graphics.draw(image, ix + drop, iy + drop, 0, scale, scale)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, ix, iy, 0, scale, scale)
end

--- icon, then a bar centred beside it
---@param fill number
---@param icon string
---@param barH number # design px
---@param color number[]
---@return number x
---@return number y
---@return number h # the bar's
function Bar.draw(fill, icon, x, y, barH, color)
    local px = UI.Theme.px
    local rowH, h = px(Bar.ICON_SIZE), px(barH)
    drawIcon(icon, x, y, rowH)
    local bx, by = x + rowH + px(GAP), y + Math.round((rowH - h) / 2)
    drawBar(fill, bx, by, px(Bar.WIDTH), h, color)
    return bx, by, h
end

---@return number # design px across icon, gap and bar
function Bar.width()
    return Bar.ICON_SIZE + GAP + Bar.WIDTH
end

return Bar
