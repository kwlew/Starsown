--- A text mesh rasterized once and redrawn through a scrolling colour shader
-- -- the animated title wordmarks. With a gradient it cycles those stops;
-- without one it cycles the whole rainbow.
--
--   local title = TextFactory.new{ text = "Starsown", font = Theme.font("title"),
--                                  gradient = Theme.titleGradient() }
--   title:update(dt)
--   title:drawChroma()

local Chroma = require("ui.shaders.chroma")
local Gradient = require("ui.shaders.gradient")

local TextFactory = {}
TextFactory.__index = TextFactory

-- the shaders are shared, so each uniform is only re-sent when it changed
local sent = { chroma = {}, gradient = {} }

---@param shader any # a love.Shader
---@param cache table # last values sent to this shader
---@param name string
---@param value any
local function sendIfChanged(shader, cache, name, value)
    if cache[name] ~= value then
        cache[name] = value
        shader:send(name, value)
    end
end

--- `size` builds its own font (with fontPath, if given); otherwise it uses
-- the font it's handed
---@param config? table # { text?: string, fontPath?: string, font?: love.Font, size?: number, color?: number[], x?: number, y?: number, limit?: number, align?: string, speed?: number, scale?: number, gradient?: number[][] }
---@return table
function TextFactory.new(config)
    config = config or {}

    local self = setmetatable({
        text = config.text or "",
        fontPath = config.fontPath,
        color = config.color or { 1, 1, 1, 1 },
        x = config.x or 0,
        y = config.y or 0,
        limit = config.limit or love.graphics.getWidth(),
        align = config.align or "left",
        speed = config.speed or 1,
        scale = config.scale or 200, -- pixels per full colour cycle
        gradient = nil,
        gradientCount = 0,
        time = 0,
    }, TextFactory)

    if config.size then
        self.font = self:newFont(config.size)
    else
        self.font = config.font or love.graphics.getFont()
    end
    self.textObject = love.graphics.newText(self.font)
    self:relayout()

    if config.gradient then self:setGradient(config.gradient) end
    return self
end

---@param size number
---@return any # a love.Font
function TextFactory:newFont(size)
    return self.fontPath and love.graphics.newFont(self.fontPath, size) or love.graphics.newFont(size)
end

function TextFactory:relayout()
    self.textObject:setf(self.text, self.limit, self.align)
    self.layoutText, self.layoutLimit, self.layoutAlign = self.text, self.limit, self.align
end

--- re-lays out only when the text or its wrap actually changed, since that
-- re-rasterizes the whole mesh
---@param text string
function TextFactory:setText(text)
    self.text = text
    if text ~= self.layoutText or self.limit ~= self.layoutLimit or self.align ~= self.layoutAlign then
        self:relayout()
    end
end

--- reallocates the font and re-rasterizes; too expensive for an animation
-- frame, so scale with a transform instead (see GameTitle.drawScaled)
---@param size number
function TextFactory:setSize(size)
    self.font = self:newFont(size)
    self.textObject = love.graphics.newText(self.font)
    self:relayout()
end

---@param colors? number[][] # 2..MAX_STOPS RGB stops; nil falls back to the rainbow
function TextFactory:setGradient(colors)
    if not colors then
        self.gradient, self.gradientCount = nil, 0
        return
    end

    local max = Gradient.MAX_STOPS
    assert(#colors >= 2, "setGradient requires at least 2 colors")
    assert(#colors <= max, "setGradient supports at most " .. max .. " colors")

    -- the shader always reads max + 1 stops (it blends stop i into i + 1)
    local padded = {}
    for i = 1, max + 1 do
        padded[i] = colors[i] or colors[1]
    end
    self.gradient, self.gradientCount = padded, #colors
end

---@param x number
---@param y number
function TextFactory:setPosition(x, y)
    self.x, self.y = x, y
end

--- advances the colour's scroll; a speed of 0 holds it still (reduced motion)
---@param dt number
function TextFactory:update(dt)
    self.time = self.time + dt * self.speed
end

--- the mesh in its flat colour, no shader
function TextFactory:draw()
    if self.text == "" then return end
    love.graphics.setColor(self.color)
    love.graphics.draw(self.textObject, self.x, self.y)
    love.graphics.setColor(1, 1, 1, 1)
end

---@return any # the configured love.Shader, or false if it failed to compile
function TextFactory:prepareShader()
    if self.gradient then
        local shader = Gradient.get()
        if not shader then return false end
        local cache = sent.gradient
        shader:send("colors", unpack(self.gradient)) -- a table per stop; live theme colours change in place
        sendIfChanged(shader, cache, "colorCount", self.gradientCount)
        sendIfChanged(shader, cache, "invScale", 1 / self.scale)
        shader:send("time", self.time)
        return shader
    end

    local shader = Chroma.get()
    if not shader then return false end
    sendIfChanged(shader, sent.chroma, "invScale", 1 / self.scale)
    shader:send("time", self.time)
    return shader
end

--- the mesh through the gradient (or rainbow) shader; falls back to the flat
-- colour if the shader couldn't compile
function TextFactory:drawChroma()
    if self.text == "" then return end
    local shader = self:prepareShader()
    if not shader then return self:draw() end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setShader(shader)
    love.graphics.draw(self.textObject, self.x, self.y)
    love.graphics.setShader()
end

--- a rectangle in the text's colours, for a matching marker.
-- The shader varies across x only, so draw in bands.
---@param bands? integer # default 12
function TextFactory:drawChromaRect(x, y, w, h, bands)
    bands = bands or 12
    local shader = self:prepareShader()
    if not shader then return end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setShader(shader)
    for i = 0, bands - 1 do
        shader:send("time", self.time + i / bands)
        local top = math.floor(y + h * i / bands)
        love.graphics.rectangle("fill", x, top, w, math.floor(y + h * (i + 1) / bands) - top)
    end
    love.graphics.setShader()
end

return TextFactory
