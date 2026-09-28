local UI = require "ui"

local Player = {}

Player.__index = Player

-- design-space units (720p baseline)
-- everything in pixels.
local RADIUS = 16 -- the 16px sprite drawn at 2x
local MAX_SPEED = 260
local ACCEL = 9
local DECEL = 10
local SPRINT_SPEED = 1.50

local KEYS = {
    left = { "a", "left" },
    right = { "d", "right" },
    up = { "w", "up" },
    down = { "s", "down" },
    shift = { "lshift", "rshift" },
}

local TEXTURE = "assets/textures/game/player.png"
local texture -- nil until first draw, false if it failed to load

--- authored in greys with a black outline, so the theme colour tints the body
---@return any # a love.Image, or false to fall back to a plain circle
local function getTexture()
    if texture == nil then
        local ok, image = pcall(love.graphics.newImage, TEXTURE)
        if ok then
            image:setFilter("nearest", "nearest")
        else
            print("[game] failed to load " .. TEXTURE .. ": " .. tostring(image))
        end
        texture = ok and image
    end
    return texture
end

local function held(action)
    return love.keyboard.isDown(unpack(KEYS[action]))
end


---@param x number # design-space position
---@param y number
function Player.new(x, y)
    return setmetatable({
        x = x,
        y = y,
        prevX = x,
        prevY = y,
        vx = 0,
        vy = 0,
    }, Player)
end

local function bounds()
    local s = UI.Theme.scale
    return love.graphics.getWidth() / s, love.graphics.getHeight() / s
end

--- one fixed simulation step; dt is always the tick length
---@param dt number
function Player:tick(dt)
    self.prevX, self.prevY = self.x, self.y

    local ix = (held("right") and 1 or 0) - (held("left") and 1 or 0)
    local iy = (held("down") and 1 or 0) - (held("up") and 1 or 0)
    local sprint = held("shift")

    local len = math.sqrt(ix * ix + iy * iy)
    if len > 0 then
        ix, iy = ix / len, iy / len end

    local speed = MAX_SPEED

    if sprint then speed = speed * SPRINT_SPEED end

    local rate = len > 0 and ACCEL or DECEL
    local t = 1 - math.exp(-rate * dt)
    self.vx = self.vx + (ix * speed - self.vx) * t
    self.vy = self.vy + (iy * speed - self.vy) * t

    self.x = self.x + self.vx * dt
    self.y = self.y + self.vy * dt
    self:clamp()
end

function Player:clamp()
    local w, h = bounds()
    local clampedX = math.max(RADIUS, math.min(w - RADIUS, self.x))
    local clampedY = math.max(RADIUS, math.min(h - RADIUS, self.y))
    if clampedX ~= self.x then self.vx = 0 end
    if clampedY ~= self.y then self.vy = 0 end
    self.x, self.y = clampedX, clampedY
end

--- drops the in-between position, for a jump that shouldn't be smoothed (a resize clamp)
function Player:snap()
    self.prevX, self.prevY = self.x, self.y
end

--- draws between the last two ticks so movement stays smooth at any frame rate
---@param alpha number # 0..1, how far the current frame is into the next tick
function Player:draw(alpha)
    local s = UI.Theme.scale
    local x = self.prevX + (self.x - self.prevX) * alpha
    local y = self.prevY + (self.y - self.prevY) * alpha
    UI.Theme.setColor(UI.Theme.colors.accent)
    local image = getTexture()
    if image then
        -- whole-number scale and pixel-snapped position keep the pixel art crisp
        local w, h = image:getDimensions()
        local scale = math.max(1, math.floor(RADIUS * 2 * s / w + 0.5))
        love.graphics.draw(image, math.floor(x * s + 0.5), math.floor(y * s + 0.5), 0,
            scale, scale, w / 2, h / 2)
    else
        love.graphics.circle("fill", x * s, y * s, RADIUS * s, 32)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return Player