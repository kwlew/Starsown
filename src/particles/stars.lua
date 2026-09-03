--- Fixed night sky behind the loading screen and menu: twinkling points plus a
-- few constellations linking some of them.

local Theme = require "ui.core.theme"
local Math = require "utils.math"
local Motion = require "ui.core.motion"

local Stars = {}
Stars.__index = Stars

local STAR_VERTEX_FORMAT = {
    { "VertexPosition", "float", 2 },
    { "VertexColor", "float", 4 },
    { "StarData", "float", 3 },
}

local twinkleShader

--- built on first use and shared. The twinkle runs in the vertex shader off
-- per-star attributes, so the whole sky is one draw call with no per-frame
-- work on the CPU.
---@return any # a love.Shader
local function getTwinkleShader()
    if not twinkleShader then
        twinkleShader = love.graphics.newShader([[
            vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
            {
                return color;
            }
        ]], [[
            attribute vec3 StarData;

            extern number time;
            extern number oscillation;

            vec4 position(mat4 transform_projection, vec4 vertex_position)
            {
                number brightness = clamp(
                    StarData.x + sin(StarData.y + time * StarData.z) * oscillation,
                    0.0, 1.0);
                VaryingColor.rgb *= brightness;
                return transform_projection * vertex_position;
            }
        ]])
    end
    return twinkleShader
end

---@param config? table # every field below may be overridden
---@return table
function Stars.new(config)
    config = config or {}
    return setmetatable({
        stars = {},
        chains = {}, -- one flat {x,y,x,y,...} polyline per constellation
        mesh = nil,
        time = 0,
        amountMin = config.amountMin or 150,
        amountMax = config.amountMax or 190,
        brightnessOscillation = config.brightnessOscillation or 0.7,
        blinkSpeedMin = config.blinkSpeedMin or 0.3,
        blinkSpeedMax = config.blinkSpeedMax or 1.2,
        constellationCountMin = config.constellationCountMin or 3,
        constellationCountMax = config.constellationCountMax or 6,
        constellationStarsMin = config.constellationStarsMin or 6,
        constellationStarsMax = config.constellationStarsMax or 10,
        constellationSpread = config.constellationSpread or 160, -- max walk distance between consecutive stars
        constellationTurn = config.constellationTurn or math.pi / 3, -- max heading change per step
        lineAlpha = config.lineAlpha or 0.2,
        alpha = config.alpha or 1, -- global fade, on top of per-star twinkle brightness
    }, Stars)
end

---@param x number
---@param y number
---@param blinkSpeedMin number
---@param blinkSpeedMax number
---@param brightnessMin number
---@param brightnessMax number
---@return table
local function newStar(x, y, blinkSpeedMin, blinkSpeedMax, brightnessMin, brightnessMax)
    return {
        x = x,
        y = y,
        brightness = Math.randRange(brightnessMin, brightnessMax),
        blinkPhase = Math.randAngle(),
        blinkSpeed = Math.randRange(blinkSpeedMin, blinkSpeedMax),
    }
end

--- random-walks a chain of stars across the screen, linking each consecutive
-- pair; keeps a heading and turns gently each step so it flows like a real
-- constellation, and reflects off screen edges instead of piling up on the border
---@param w number
---@param h number
function Stars:spawnConstellation(w, h)
    local starCount = Math.randInt(self.constellationStarsMin, self.constellationStarsMax)
    local margin = math.min(self.constellationSpread, math.min(w, h) / 3)
    local x = Math.randRange(margin, math.max(margin, w - margin))
    local y = Math.randRange(margin, math.max(margin, h - margin))
    local heading = Math.randAngle()
    local chain = {}

    for _ = 1, starCount do
        local star = newStar(x, y, self.blinkSpeedMin, self.blinkSpeedMax, 0.85, 1.0) -- brighter than background stars
        self.stars[#self.stars + 1] = star

        chain[#chain + 1] = star.x
        chain[#chain + 1] = star.y

        heading = heading + Math.randRange(-self.constellationTurn, self.constellationTurn)
        local dist = Math.randRange(self.constellationSpread * 0.55, self.constellationSpread)
        local nx = x + math.cos(heading) * dist
        local ny = y + math.sin(heading) * dist

        if nx < margin or nx > w - margin then heading = math.pi - heading end
        if ny < margin or ny > h - margin then heading = -heading end
        x = Math.clamp(x + math.cos(heading) * dist, 0, w)
        y = Math.clamp(y + math.sin(heading) * dist, 0, h)
    end

    if #chain >= 4 then -- love.graphics.line needs at least two points
        self.chains[#self.chains + 1] = chain
    end
end

--- regenerates the whole sky at a fixed 1920x1080, never at the window size:
-- the window is only a viewport onto it, so a resize doesn't reshuffle the stars
function Stars:spawnStars()
    local w, h = 1920, 1080
    self.stars = {}
    self.chains = {}

    for _ = 1, Math.randInt(self.amountMin, self.amountMax) do
        self.stars[#self.stars + 1] = newStar(Math.randRange(0, w), Math.randRange(0, h),
            self.blinkSpeedMin, self.blinkSpeedMax, 0.6, 1.0)
    end

    for _ = 1, Math.randInt(self.constellationCountMin, self.constellationCountMax) do
        self:spawnConstellation(w, h)
    end

    self:buildBatches()
end

--- bakes every star into one static point mesh, twinkle parameters and all
function Stars:buildBatches()
    local vertices = {}
    for i, s in ipairs(self.stars) do
        vertices[i] = {
            s.x, s.y,
            1, 1, 1, 1,
            s.brightness, s.blinkPhase, s.blinkSpeed,
        }
    end
    self.mesh = love.graphics.newMesh(STAR_VERTEX_FORMAT, vertices, "points", "static")
    getTwinkleShader()
end

--- only advances the clock; the twinkle itself is the shader's job
---@param dt number
function Stars:update(dt)
    self.time = self.time + dt
end

--- constellation lines, then the whole sky in a single shaded draw
function Stars:draw()
    if self.alpha <= 0 or not self.mesh then return end

    Theme.setColor(Theme.colors.textDim, self.lineAlpha * self.alpha)
    for _, chain in ipairs(self.chains) do
        love.graphics.line(chain)
    end

    local oscillation = Motion.reduced and 0 or self.brightnessOscillation -- reduced motion: no twinkle
    local shader = getTwinkleShader()
    shader:send("time", self.time)
    shader:send("oscillation", oscillation)

    local prevSize = love.graphics.getPointSize()
    love.graphics.setPointSize(2)
    Theme.setColor(Theme.colors.star, self.alpha)
    love.graphics.setShader(shader)
    love.graphics.draw(self.mesh)
    love.graphics.setShader()
    love.graphics.setPointSize(prevSize)
end

return Stars
