local TextFactory = {}

-- Max distinct color stops a gradient can hold (excludes the auto-added wrap slot).
local MAX_GRADIENT_COLORS = 8

-- Lazily built so each shader is only compiled if it's actually used.
local chromaShader = nil
local gradientShader = nil

local function getChromaShader()
    if not chromaShader then
        chromaShader = love.graphics.newShader([[
            extern number time;
            extern number scale;

            vec3 hsv2rgb(vec3 c)
            {
                vec4 k = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
                vec3 p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
                return c.z * mix(k.xxx, clamp(p - k.xxx, 0.0, 1.0), c.y);
            }

            vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
            {
                vec4 texcolor = Texel(texture, texture_coords);
                number hue = fract(screen_coords.x / scale + time);
                vec3 rgb = hsv2rgb(vec3(hue, 1.0, 1.0));
                return vec4(rgb, texcolor.a) * color;
            }
        ]])
    end
    return chromaShader
end

-- Cycles through an arbitrary list of colors (e.g. red -> blue -> repeat)
-- instead of the fixed rainbow. `colors[8]` holds the wrap-around slot back to
-- the first stop, so the loop index can always read `colors[i + 1]` safely.
local function getGradientShader()
    if not gradientShader then
        gradientShader = love.graphics.newShader([[
            extern vec3 colors[9];
            extern number colorCount;
            extern number time;
            extern number scale;

            vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
            {
                vec4 texcolor = Texel(texture, texture_coords);

                number t = fract(screen_coords.x / scale + time);
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

                vec3 rgb = mix(c1, c2, frac);
                return vec4(rgb, texcolor.a) * color;
            }
        ]])
    end
    return gradientShader
end

function TextFactory:new(config)
    config = config or {}

    local obj = {
        text = config.text or "",
        fontPath = config.fontPath, -- optional .ttf/.otf path used when (re)sizing
        color = config.color or { 1, 1, 1, 1 },
        x = config.x or 0,
        y = config.y or 0,
        limit = config.limit or love.graphics.getWidth(),
        align = config.align or "left",
        speed = config.speed or 1, -- how fast the chroma cycles
        scale = config.scale or 200, -- pixel span of one full color cycle
        gradient = nil,
        gradientCount = 0,
        time = 0
    }

    if config.size then
        obj.font = config.fontPath and love.graphics.newFont(config.fontPath, config.size) or love.graphics.newFont(config.size)
    else
        obj.font = config.font or love.graphics.getFont()
    end

    setmetatable(obj, { __index = self })

    -- Cached glyph mesh: printf-style wrapping/rasterization is redone here
    -- only when the text or font actually changes, not on every draw call.
    obj.textObject = love.graphics.newTextBatch(obj.font)
    obj.textObject:setf(obj.text, obj.limit, obj.align)

    if config.gradient then
        obj:setGradient(config.gradient)
    end

    return obj
end

function TextFactory:setText(text)
    self.text = text
    self.textObject:setf(self.text, self.limit, self.align)
end

-- Rebuilds the font at the given point size, using fontPath if one was
-- set (via config or a prior call), otherwise LOVE's default font.
function TextFactory:setSize(size)
    if self.fontPath then
        self.font = love.graphics.newFont(self.fontPath, size)
    else
        self.font = love.graphics.newFont(size)
    end

    self.textObject = love.graphics.newTextBatch(self.font)
    self.textObject:setf(self.text, self.limit, self.align)
end

-- Sets the list of colors (e.g. {{1,0,0},{0,0,1}} for red -> blue) that
-- drawChroma cycles through and repeats. Pass nil to fall back to the
-- default rainbow. Each color is {r, g, b} in the 0-1 range.
function TextFactory:setGradient(colors)
    if not colors then
        self.gradient = nil
        self.gradientCount = 0
        return
    end

    assert(#colors >= 2, "setGradient requires at least 2 colors")
    assert(#colors <= MAX_GRADIENT_COLORS, "setGradient supports at most " .. MAX_GRADIENT_COLORS .. " colors")

    local padded = {}
    for i = 1, MAX_GRADIENT_COLORS + 1 do
        padded[i] = colors[i] or colors[1]
    end

    self.gradient = padded
    self.gradientCount = #colors
end

function TextFactory:setPosition(x, y)
    self.x = x
    self.y = y
end

function TextFactory:update(dt)
    self.time = self.time + dt * self.speed
end

function TextFactory:draw()
    if self.text == "" then return end

    love.graphics.setColor(self.color)
    love.graphics.draw(self.textObject, self.x, self.y)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Draws the cached text mesh with a scrolling color cycle driven by a
-- shader: the custom gradient set via setGradient, or a rainbow if none
-- was set. Because the glyph mesh is cached (see setText/setSize), this
-- only re-runs the fragment shader per pixel, not the text layout/raster.
function TextFactory:drawChroma()
    if self.text == "" then return end

    local shader

    if self.gradient then
        shader = getGradientShader()
        shader:send("colors", unpack(self.gradient))
        shader:send("colorCount", self.gradientCount)
    else
        shader = getChromaShader()
    end

    shader:send("time", self.time)
    shader:send("scale", self.scale)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setShader(shader)
    love.graphics.draw(self.textObject, self.x, self.y)
    love.graphics.setShader()
end

return TextFactory
