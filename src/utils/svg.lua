local Math = require "src.utils.math"

local SVG = {}

local function tokenize(d)
    local tokens, i, n = {}, 1, #d
    while i <= n do
        local c = d:sub(i, i)
        if c:match("%a") then
            tokens[#tokens + 1] = { cmd = c }
            i = i + 1
        elseif c:match("%s") or c == "," then
            i = i + 1
        else
            local j = i
            if d:sub(j, j):match("[%+%-]") then j = j + 1 end
            while j <= n and d:sub(j, j):match("%d") do j = j + 1 end
            if d:sub(j, j) == "." then
                j = j + 1
                while j <= n and d:sub(j, j):match("%d") do j = j + 1 end
            end
            tokens[#tokens + 1] = { num = tonumber(d:sub(i, j - 1)) }
            i = j
        end
    end
    return tokens
end

local function flatten(d, steps)
    local tokens = tokenize(d)
    local pts, idx = {}, 1
    local function num() local t = tokens[idx]; idx = idx + 1; return t.num end

    local cx, cy, sx, sy, cmd = 0, 0, 0, 0, nil
    local function add(x, y) pts[#pts + 1] = x / SVG_SIZE; pts[#pts + 1] = y / SVG_SIZE end
    local function cubic(x1, y1, x2, y2, x3, y3)
        local x0, y0 = cx, cy
        for s = 1, steps do
            local t = s / steps
            local mt = 1 - t
            add(mt * mt * mt * x0 + 3 * mt * mt * t * x1 + 3 * mt * t * t * x2 + t * t * t * x3,
                mt * mt * mt * y0 + 3 * mt * mt * t * y1 + 3 * mt * t * t * y2 + t * t * t * y3)
        end
        cx, cy = x3, y3
    end

    while idx <= #tokens do
        if tokens[idx].cmd then cmd = tokens[idx].cmd; idx = idx + 1 end
        if cmd == "M" then
            cx, cy = num(), num(); sx, sy = cx, cy; add(cx, cy); cmd = "L"
        elseif cmd == "m" then
            cx, cy = cx + num(), cy + num(); sx, sy = cx, cy; add(cx, cy); cmd = "l"
        elseif cmd == "L" then
            cx, cy = num(), num(); add(cx, cy)
        elseif cmd == "l" then
            cx, cy = cx + num(), cy + num(); add(cx, cy)
        elseif cmd == "C" then
            cubic(num(), num(), num(), num(), num(), num())
        elseif cmd == "c" then
            cubic(cx + num(), cy + num(), cx + num(), cy + num(), cx + num(), cy + num())
        elseif cmd == "z" or cmd == "Z" then
            cx, cy = sx, sy
        else
            error("githubMark: unsupported path command '" .. tostring(cmd) .. "'")
        end
    end
    return pts
end

local UNIT_POINTS = flatten(PATH, 10)

local function buildMesh()
    local verts = {}
    for i = 1, #UNIT_POINTS, 2 do
        verts[#verts + 1] = { UNIT_POINTS[i], UNIT_POINTS[i + 1] }
    end
    return love.graphics.newMesh(verts, "fan")
end

local function fillMark(x, y, size)
    mesh = mesh or buildMesh()

    love.graphics.stencil(function()
        love.graphics.push()
        love.graphics.translate(x, y)
        love.graphics.scale(size, size)
        love.graphics.draw(mesh)
        love.graphics.pop()
    end, "invert", 1)

    love.graphics.setStencilTest("notequal", 0)
    love.graphics.rectangle("fill", x, y, size, size)
    love.graphics.setStencilTest()
end

local function paint(x, y, size, color, glow)
    if glow > 0 then
        -- Glyph-shaped halo: the same silhouette stamped a few times at
        -- increasing size, additively, so the glow hugs the logo's outline
        -- instead of sitting behind it as a square blob.
        love.graphics.setBlendMode("add")
        for i = GLOW_LAYERS, 1, -1 do
            local grow = i * size * GLOW_SPREAD
            love.graphics.setColor(color[1], color[2], color[3], GLOW_ALPHA * glow / i)
            fillMark(x - grow / 2, y - grow / 2, size + grow)
        end
        love.graphics.setBlendMode("alpha")
    end

    love.graphics.setColor(color)
    fillMark(x, y, size)
end