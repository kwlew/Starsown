--- Plans and paints individual gas clouds onto a layer.

local Math = require("utils.math")
local Resources = require("particles.nebula.resources")

local Clouds = {}

--- Box-Muller: dense core, wispy edge
---@return number
local function gaussian()
    local u1 = math.max(1e-9, math.random())
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * math.random())
end

---@return number
---@return number
local function rotate(x, y, angle)
    local c, s = math.cos(angle), math.sin(angle)
    return x * c - y * s, x * s + y * c
end

--- placed on a ring, keeping the centre clear
---@param cfg table # the Nebula's tuning fields
---@param w number # design width
---@param h number # design height
---@return table
function Clouds.plan(cfg, w, h)
    local angle = Math.randAngle()
    local ring = Math.randRange(cfg.centerHole, cfg.edgeReach)
    local palette = cfg.colors
    return {
        x = w / 2 + math.cos(angle) * ring * w,
        y = h / 2 + math.sin(angle) * ring * h,
        radius = Math.randRange(cfg.radiusMin, cfg.radiusMax) * h,
        tilt = Math.randRange(0, math.pi),
        aspect = Math.randRange(cfg.aspectMin, cfg.aspectMax),
        core = palette[math.random(#palette)],
        rim = palette[math.random(#palette)],
        stamps = Math.randInt(cfg.stampsMin, cfg.stampsMax),
    }
end

--- the gas: stamps tinted core-to-rim by distance; caller sets "add"
---@param cfg table
---@param cloud table
function Clouds.stamp(cfg, cloud)
    local image, origin = Resources.blob(), Resources.BLOB_SIZE / 2
    for _ = 1, cloud.stamps do
        local ox = gaussian() * cloud.radius * 0.42
        local oy = gaussian() * cloud.radius * 0.42 * cloud.aspect
        local dx, dy = rotate(ox, oy, cloud.tilt)

        local dist = math.min(1, Math.length(ox, oy) / cloud.radius)
        local alpha = Math.randRange(cfg.stampAlphaMin, cfg.stampAlphaMax) * (0.35 + 0.65 * (1 - dist))
        local r, g, b = Math.Color.lerp(cloud.core, cloud.rim, dist)
        local sx = cloud.radius * Math.randRange(cfg.stampSizeMin, cfg.stampSizeMax) / Resources.BLOB_SIZE

        love.graphics.setColor(r, g, b, alpha)
        love.graphics.draw(image, cloud.x + dx, cloud.y + dy, Math.randAngle(),
            sx, sx * Math.randRange(0.6, 1.0), origin, origin)
    end
end

--- dark lanes: thin chains drawn back; caller sets "subtract"
---@param cfg table
---@param cloud table
function Clouds.carveLanes(cfg, cloud)
    local image, origin, size = Resources.blob(), Resources.BLOB_SIZE / 2, Resources.BLOB_SIZE
    for _ = 1, cfg.lanesPerCloud do
        local dx, dy = rotate(gaussian() * cloud.radius * 0.35, gaussian() * cloud.radius * 0.35, cloud.tilt)
        local x, y = cloud.x + dx, cloud.y + dy
        local heading = cloud.tilt + Math.randRange(-0.6, 0.6)
        local segment = cloud.radius * Math.randRange(0.30, 0.55)
        local thickness = cloud.radius * Math.randRange(0.07, 0.16)
        local alpha = Math.randRange(cfg.laneAlphaMin, cfg.laneAlphaMax)

        for _ = 1, cfg.laneSegments do
            love.graphics.setColor(1, 1, 1, alpha)
            love.graphics.draw(image, x, y, heading, segment / size, thickness / size, origin, origin)
            heading = heading + Math.randRange(-cfg.laneTurn, cfg.laneTurn)
            x = x + math.cos(heading) * segment * 0.6
            y = y + math.sin(heading) * segment * 0.6
        end
    end
end

return Clouds
