--- Star field GPU side: sprite, twinkle shader, static mesh.

local Math = require("utils.math")

local Render = {}

local VERTEX_FORMAT = {
    { "VertexPosition", "float", 2 },
    { "VertexTexCoord", "float", 2 },
    { "StarData", "float", 3 }, -- brightness, blink phase, blink speed
    { "StarTint", "float", 2 }, -- which accent, how far toward it
}

local SPRITE_SIZE = 64
Render.SPRITE_CORE = 0.16 -- core radius / sprite half-width
local QUAD_CORNERS = { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, -1 }, { 1, 1 }, { -1, 1 } }

local shader, sprite

--- twinkle and tint per vertex: one draw call
---@return any # a love.Shader
function Render.shader()
    shader = shader or love.graphics.newShader([[
        vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
        {
            return Texel(texture, texture_coords) * color;
        }
    ]], [[
        attribute vec3 StarData;
        attribute vec2 StarTint;

        extern number time;
        extern number oscillation;
        extern vec3 tintA;
        extern vec3 tintB;

        vec4 position(mat4 transform_projection, vec4 vertex_position)
        {
            number brightness = clamp(
                StarData.x + sin(StarData.y + time * StarData.z) * oscillation, 0.0, 1.0);
            vec3 tint = mix(tintA, tintB, StarTint.x);
            VaryingColor.rgb *= mix(vec3(1.0), tint, StarTint.y) * brightness;
            return transform_projection * vertex_position;
        }
    ]])
    return shader
end

--- a round core with a faint halo
---@return any # a love.Image
local function getSprite()
    if sprite then return sprite end
    local data = love.image.newImageData(SPRITE_SIZE, SPRITE_SIZE)
    local center = (SPRITE_SIZE - 1) / 2
    local core = Render.SPRITE_CORE
    data:mapPixel(function(x, y)
        local d = Math.length(x - center, y - center) / center
        if d >= 1 then return 1, 1, 1, 0 end
        local solid = 1 - Math.clamp01((d - core * 0.6) / (core * 0.8))
        local halo = 0.22 * math.exp(-(d / 0.4) ^ 2) * (1 - d)
        return 1, 1, 1, math.max(solid, halo)
    end)
    sprite = love.graphics.newImage(data)
    sprite:setFilter("linear", "linear")
    return sprite
end

---@param stars table[]
---@return any # a love.Mesh
function Render.buildMesh(stars)
    local vertices = {}
    for _, s in ipairs(stars) do
        local half = s.size / Render.SPRITE_CORE
        for _, c in ipairs(QUAD_CORNERS) do
            vertices[#vertices + 1] = {
                s.x + c[1] * half, s.y + c[2] * half,
                (c[1] + 1) / 2, (c[2] + 1) / 2,
                s.brightness, s.blinkPhase, s.blinkSpeed,
                s.tint, s.tintAmount,
            }
        end
    end
    local mesh = love.graphics.newMesh(VERTEX_FORMAT, vertices, "triangles", "static")
    mesh:setTexture(getSprite())
    return mesh
end

return Render
