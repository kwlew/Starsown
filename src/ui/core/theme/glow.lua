--- The layered additive glow drawn around focused rows, and the canvas cache
-- that bakes it for sizes that repeat.

local Colors = require("ui.core.theme.colors")
local Metrics = require("ui.core.theme.metrics")

local Glow = {}

local MAX_GLOW_CACHE = 16

local glowCache = {}
local glowCacheCount = 0

---@param time number seconds
---@return number # 0.2..1, the shared breathing multiplier for glows
function Glow.pulse(time)
    return 0.6 + 0.4 * math.sin(time * 3)
end

--- bakes the layered glow for one rectangle size into a canvas, restoring
-- every piece of graphics state it borrows
---@param w number
---@param h number
---@param radius number # corner radius
---@return table # { canvas: love.Canvas, pad: number }
local function build(w, h, radius)
    local m = Metrics.metrics
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
local function get(w, h, radius)
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
        glow = build(w, h, radius)
        byRadius[radius] = glow
        glowCacheCount = glowCacheCount + 1
    end
    return glow
end

--- drops every baked glow; they were built at the old metrics
function Glow.clearCache()
    glowCache = {}
    glowCacheCount = 0
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
function Glow.rect(x, y, w, h, radius, intensity, color, cached)
    color = color or Colors.colors.glow
    if not cached then
        local m = Metrics.metrics
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

    local glow = get(w, h, radius)
    local r, g, b = color[1] * intensity, color[2] * intensity, color[3] * intensity

    love.graphics.setBlendMode("add", "premultiplied")
    love.graphics.setColor(r, g, b, 1)
    love.graphics.draw(glow.canvas, x - glow.pad, y - glow.pad)
    love.graphics.setBlendMode("alpha")
end

return Glow
