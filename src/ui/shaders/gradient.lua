--- Like chroma, but cycles through a given list of colour stops instead of
-- the whole hue wheel. Uniforms: colors (MAX_STOPS + 1 vec3s, padded),
-- colorCount, time, invScale.

local lazy = require("ui.shaders.lazy")

local Gradient = {}

Gradient.MAX_STOPS = 8

Gradient.get = lazy("gradient", [[
    extern vec3 colors[9];
    extern number colorCount;
    extern number time;
    extern number invScale;

    vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
    {
        vec4 texcolor = Texel(texture, texture_coords);

        number t = fract(screen_coords.x * invScale + time);
        number scaled = t * colorCount;
        number idx = floor(scaled);
        number frac = scaled - idx;

        vec3 c1 = colors[0];
        vec3 c2 = colors[0];
        for (int i = 0; i < 8; i++) {
            if (float(i) == idx) {
                c1 = colors[i];
                c2 = colors[i + 1];
            }
        }

        return vec4(mix(c1, c2, frac), texcolor.a) * color;
    }
]])

return Gradient
