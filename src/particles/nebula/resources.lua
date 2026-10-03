--- Shared GPU resources for baking the nebula, built once.

local Resources = {}

Resources.BLOB_SIZE = 128

local blob, bakeFormat, noiseShader

--- domain-warped fBm that breaks gas into wisps and filaments
---@return any # a love.Shader
function Resources.noiseShader()
    noiseShader = noiseShader or love.graphics.newShader([[
        extern vec2 seed;
        extern number scale;    // noise cells across the layer's height
        extern number aspect;   // layer width / height
        extern number strength; // 0 keeps the gas, 1 carves it away

        number hash(vec2 p)
        {
            vec3 p3 = fract(vec3(p.xyx) * 0.1031);
            p3 += dot(p3, p3.yzx + 33.33);
            return fract((p3.x + p3.y) * p3.z);
        }

        number noise(vec2 p)
        {
            vec2 i = floor(p);
            vec2 f = fract(p);
            vec2 u = f * f * (3.0 - 2.0 * f);
            return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
                       mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
        }

        number fbm(vec2 p)
        {
            number value = 0.0;
            number amplitude = 0.5;
            for (int i = 0; i < 5; i++) {
                value += amplitude * noise(p);
                p = p * 2.03 + vec2(17.1, 9.2);
                amplitude *= 0.5;
            }
            return value;
        }

        vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
        {
            vec2 p = texture_coords * vec2(aspect, 1.0) * scale + seed;
            vec2 warp = vec2(fbm(p), fbm(p + vec2(5.2, 1.3)));
            number n = fbm(p + 2.0 * warp);
            number body = smoothstep(0.3, 0.7, n);
            number ridge = 1.0 - smoothstep(0.0, 0.06, abs(n - 0.5));
            number mask = 1.0 - strength + strength * (0.6 * body + 1.4 * ridge);
            return Texel(texture, texture_coords) * color * mask;
        }
    ]])
    return noiseShader
end

--- half-float where possible; 8-bit rounds the faint stamps away
---@return string
function Resources.bakeFormat()
    bakeFormat = bakeFormat or (love.graphics.getCanvasFormats().rgba16f and "rgba16f" or "normal")
    return bakeFormat
end

--- a soft round stamp with cubic alpha falloff
---@return any # a love.Image
function Resources.blob()
    if blob then return blob end
    local size = Resources.BLOB_SIZE
    local data = love.image.newImageData(size, size)
    local center = (size - 1) / 2
    data:mapPixel(function(x, y)
        local dx, dy = (x - center) / center, (y - center) / center
        local d2 = dx * dx + dy * dy
        if d2 >= 1 then return 1, 1, 1, 0 end
        local a = 1 - d2
        return 1, 1, 1, a * a * a
    end)
    blob = love.graphics.newImage(data)
    blob:setFilter("linear", "linear")
    return blob
end

return Resources
