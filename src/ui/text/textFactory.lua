local TextFactory = {}
TextFactory.__index = TextFactory

local graphics = love.graphics
local unpack = unpack or table.unpack

local MAX_GRADIENT_COLORS = 8

local chromaShader = nil
local gradientShader = nil
local chromaScale = nil
local gradientScale = nil
local gradientColorCount = nil

--- built on first use and shared; the rainbow fallback when no gradient is set
---@return any # a love.Shader
local function getChromaShader()
    if not chromaShader then
        chromaShader = graphics.newShader([[
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
                vec3 rgb = hsv2rgb(vec3(hue, 1.0, 1.0));
                return vec4(rgb, texcolor.a) * color;
            }
        ]])
    end
    return chromaShader
end

--- built on first use and shared; interpolates between the theme's title stops
---@return any # a love.Shader
local function getGradientShader()
    if not gradientShader then
        gradientShader = graphics.newShader([[
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

                vec3 rgb = mix(c1, c2, frac);
                return vec4(rgb, texcolor.a) * color;
            }
        ]])
    end
    return gradientShader
end

--- a text mesh rasterized once and redrawn through a shader, for the animated
-- title wordmarks. `size` builds its own font (with fontPath, if given);
-- otherwise it uses the font it's handed.
---@param config? table # { text?: string, fontPath?: string, font?: love.Font, size?: number, color?: number[], x?: number, y?: number, limit?: number, align?: string, speed?: number, scale?: number, gradient?: number[][] }
---@return table
function TextFactory:new(config)
    config = config or {}

    local obj = {
        text = config.text or "",
        fontPath = config.fontPath,
        color = config.color or { 1, 1, 1, 1 },
        x = config.x or 0,
        y = config.y or 0,
        limit = config.limit or graphics.getWidth(),
        align = config.align or "left",
        speed = config.speed or 1,
        scale = config.scale or 200,
        gradient = nil,
        gradientCount = 0,
        time = 0
    }

    if config.size then
        obj.font = config.fontPath and graphics.newFont(config.fontPath, config.size) or graphics.newFont(config.size)
    else
        obj.font = config.font or graphics.getFont()
    end

    setmetatable(obj, self)

    obj.textObject = graphics.newText(obj.font)
    obj.textObject:setf(obj.text, obj.limit, obj.align)
    obj.layoutText = obj.text
    obj.layoutLimit = obj.limit
    obj.layoutAlign = obj.align

    if config.gradient then
        obj:setGradient(config.gradient)
    end

    return obj
end

--- re-lays out only when the text or its wrap actually changed, since that
-- re-rasterizes the whole mesh
---@param text string
function TextFactory:setText(text)
    self.text = text
    if text == self.layoutText and self.limit == self.layoutLimit and self.align == self.layoutAlign then
        return
    end

    self.textObject:setf(text, self.limit, self.align)
    self.layoutText = text
    self.layoutLimit = self.limit
    self.layoutAlign = self.align
end

--- reallocates the font and re-rasterizes; too expensive for an animation
-- frame, so scale with a transform instead (see ui/text/gameTitle.lua)
---@param size number
function TextFactory:setSize(size)
    if self.fontPath then
        self.font = graphics.newFont(self.fontPath, size)
    else
        self.font = graphics.newFont(size)
    end

    self.textObject = graphics.newText(self.font)
    self.textObject:setf(self.text, self.limit, self.align)
    self.layoutText = self.text
    self.layoutLimit = self.limit
    self.layoutAlign = self.align
end

---@param colors? number[][] # 2..8 RGB stops; nil falls back to the rainbow shader
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

---@param x number
---@param y number
function TextFactory:setPosition(x, y)
    self.x = x
    self.y = y
end

--- advances the gradient's scroll; a speed of 0 holds it still (reduced motion)
---@param dt number
function TextFactory:update(dt)
    self.time = self.time + dt * self.speed
end

--- the mesh in its flat colour, no shader
function TextFactory:draw()
    if self.text == "" then return end

    graphics.setColor(self.color)
    graphics.draw(self.textObject, self.x, self.y)
    graphics.setColor(1, 1, 1, 1)
end

--- the mesh through the gradient shader, or the rainbow one when no gradient
-- is set. Hue keys off screen x, so the gradient's period scales with the text.
function TextFactory:drawChroma()
    if self.text == "" then return end

    local shader

    if self.gradient then
        shader = getGradientShader()
        shader:send("colors", unpack(self.gradient))
        if gradientColorCount ~= self.gradientCount then
            gradientColorCount = self.gradientCount
            shader:send("colorCount", gradientColorCount)
        end
        if gradientScale ~= self.scale then
            gradientScale = self.scale
            shader:send("invScale", 1 / gradientScale)
        end
    else
        shader = getChromaShader()
        if chromaScale ~= self.scale then
            chromaScale = self.scale
            shader:send("invScale", 1 / chromaScale)
        end
    end

    shader:send("time", self.time)

    graphics.setColor(1, 1, 1, 1)
    graphics.setShader(shader)
    graphics.draw(self.textObject, self.x, self.y)
    graphics.setShader()
end

return TextFactory
