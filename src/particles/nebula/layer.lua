--- One nebula layer's canvas: drawing into it, then finalizing it.

local Math = require("utils.math")
local Resources = require("particles.nebula.resources")

local Layer = {}

---@param w number
---@param h number
---@return any # a cleared float love.Canvas
function Layer.newCanvas(w, h)
    local canvas = love.graphics.newCanvas(w, h, { format = Resources.bakeFormat() })
    canvas:setFilter("linear", "linear")
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.pop()
    return canvas
end

--- draws in design space, restoring all state even on error
---@param canvas any
---@param scale number # canvas pixels per design pixel
---@param offsetX number # design px
---@param offsetY number
---@param blendMode string
---@param draw fun()
function Layer.paint(canvas, scale, offsetX, offsetY, blendMode, draw)
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.origin()
    love.graphics.scale(scale)
    love.graphics.translate(offsetX, offsetY)
    love.graphics.setBlendMode(blendMode)
    local ok, err = pcall(draw)
    love.graphics.pop()
    if not ok then error(err, 0) end
end

--- applies the noise pass and clamps into an 8-bit canvas
---@param canvas any # the float bake canvas; released
---@param cfg table # { noiseScale, noiseStrength }
---@return any # a love.Canvas
function Layer.finalize(canvas, cfg)
    local w, h = canvas:getDimensions()
    local stored = love.graphics.newCanvas(w, h)
    stored:setFilter("linear", "linear")

    local shader = Resources.noiseShader()
    shader:send("seed", { Math.randRange(0, 100), Math.randRange(0, 100) })
    shader:send("scale", cfg.noiseScale)
    shader:send("aspect", w / h)
    shader:send("strength", cfg.noiseStrength)

    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setCanvas(stored)
    love.graphics.setBlendMode("replace", "premultiplied")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setShader(shader)
    love.graphics.draw(canvas)
    love.graphics.pop()
    canvas:release()
    return stored
end

return Layer
