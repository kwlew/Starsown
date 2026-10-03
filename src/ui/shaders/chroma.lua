--- A rainbow that scrolls horizontally across whatever is drawn, keyed off
-- screen x. Uniforms: time, invScale (1 / pixels per full hue cycle).

local lazy = require("ui.shaders.lazy")

return { get = lazy("chroma", [[
    extern number time;
    extern number invScale;

    vec3 hsv2rgb(vec3 c)
    {
        vec4 k = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
        vec3 p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
        return c.z * mix(k.xxx, clamp(p - k.xxx, 0.0, 1.0), c.y);
    }

    vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
    {
        vec4 texcolor = Texel(texture, texture_coords);
        number hue = fract(screen_coords.x * invScale + time);
        return vec4(hsv2rgb(vec3(hue, 1.0, 1.0)), texcolor.a) * color;
    }
]]) }
