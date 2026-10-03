--- Recolours an image as shades of the draw colour: each pixel's brightness,
-- relative to the image's brightest pixel, scales the tint, so outline and
-- shading survive. Uniform: peakLuma (see Tint.peakLuma).

local lazy = require("ui.shaders.lazy")

local Tint = {}

Tint.get = lazy("tint", [[
    uniform float peakLuma;
    vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
        vec4 texel = Texel(tex, uv);
        float luma = dot(texel.rgb, vec3(0.299, 0.587, 0.114)) / peakLuma;
        return vec4(min(color.rgb * luma, vec3(1.0)), texel.a * color.a);
    }
]])

--- the brightest visible pixel's luma, which the shader divides by
---@param data any # love.ImageData
---@return number
function Tint.peakLuma(data)
    local peak = 0
    data:mapPixel(function(_, _, r, g, b, a)
        if a > 0 then peak = math.max(peak, 0.299 * r + 0.587 * g + 0.114 * b) end
        return r, g, b, a
    end)
    return math.max(peak, 1 / 255)
end

return Tint
