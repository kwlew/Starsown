--- Parses a single SVG path string into flat points: no drawing, no love
-- calls. Bezier curves and arcs are flattened into line segments.
--
--   local points, subpaths = SvgPath.flatten(d, 24, 10)
--
-- Path commands supported: M/m, L/l, C/c, A/a (elliptical arc), Z/z --
-- covers every mark fed to it so far; add a case to flatten() for anything else.

local Math = require("utils.math")

local SvgPath = {}

--- splits a path string into { cmd = "M" } and { num = 12 } tokens. Arc flags
-- are single digits with no separator ("a1 1 0 010 2"), so they're read one
-- character at a time rather than as numbers.
---@param d string # an SVG path's `d` attribute
---@return table[] tokens
local function tokenize(d)
    local tokens, i, n = {}, 1, #d
    local cmd, argIndex = nil, 0
    while i <= n do
        local c = d:sub(i, i)
        if c:match("%a") then
            cmd, argIndex = c, 0
            tokens[#tokens + 1] = { cmd = c }
            i = i + 1
        elseif c:match("%s") or c == "," then
            i = i + 1
        else
            local isFlag = (cmd == "a" or cmd == "A")
                and (argIndex % 7 == 3 or argIndex % 7 == 4)
            local j = i
            if isFlag then
                j = i + 1
            else
                if d:sub(j, j):match("[%+%-]") then j = j + 1 end
                while j <= n and d:sub(j, j):match("%d") do j = j + 1 end
                if d:sub(j, j) == "." then
                    j = j + 1
                    while j <= n and d:sub(j, j):match("%d") do j = j + 1 end
                end
            end
            tokens[#tokens + 1] = { num = tonumber(d:sub(i, j - 1)) }
            argIndex = argIndex + 1
            i = j
        end
    end
    return tokens
end

--- endpoint-to-center parameterization
---@param x0 number # current point
---@param y0 number # current point
---@param rx number
---@param ry number
---@param rotDeg number # x-axis rotation, degrees
---@param largeArc boolean
---@param sweep boolean
---@param x number endpoint
---@param y number endpoint
---@param steps integer # segments to flatten into
---@return number[] # flat x, y pairs
local function arcPoints(x0, y0, rx, ry, rotDeg, largeArc, sweep, x, y, steps)
    rx, ry = math.abs(rx), math.abs(ry)
    if rx == 0 or ry == 0 or (x0 == x and y0 == y) then
        return { x, y } -- degenerate arc: SVG treats it as a straight line
    end

    local phi = math.rad(rotDeg)
    local cosPhi, sinPhi = math.cos(phi), math.sin(phi)

    local dx2, dy2 = (x0 - x) / 2, (y0 - y) / 2
    local x1p = cosPhi * dx2 + sinPhi * dy2
    local y1p = -sinPhi * dx2 + cosPhi * dy2

    local rxSq, rySq = rx * rx, ry * ry
    local x1pSq, y1pSq = x1p * x1p, y1p * y1p
    local lambda = x1pSq / rxSq + y1pSq / rySq
    if lambda > 1 then
        local s = math.sqrt(lambda)
        rx, ry = rx * s, ry * s
        rxSq, rySq = rx * rx, ry * ry
    end

    local sign = (largeArc ~= sweep) and 1 or -1
    local num = rxSq * rySq - rxSq * y1pSq - rySq * x1pSq
    local den = rxSq * y1pSq + rySq * x1pSq
    local co = (den > 0 and num > 0) and sign * math.sqrt(num / den) or 0
    local cxp = co * (rx * y1p / ry)
    local cyp = co * (-ry * x1p / rx)

    local cx = cosPhi * cxp - sinPhi * cyp + (x0 + x) / 2
    local cy = sinPhi * cxp + cosPhi * cyp + (y0 + y) / 2

    --- signed angle from (ux,uy) to (vx,vy): cross product for sign, dot
    -- product (clamped against float drift) for magnitude
    local function angleBetween(ux, uy, vx, vy)
        local dot = ux * vx + uy * vy
        local len = math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
        local a = math.acos(Math.clamp(dot / len, -1, 1))
        if ux * vy - uy * vx < 0 then a = -a end
        return a
    end

    local ux, uy = (x1p - cxp) / rx, (y1p - cyp) / ry
    local vx, vy = (-x1p - cxp) / rx, (-y1p - cyp) / ry

    local theta1 = angleBetween(1, 0, ux, uy)
    local dtheta = angleBetween(ux, uy, vx, vy)
    if not sweep and dtheta > 0 then dtheta = dtheta - 2 * math.pi end
    if sweep and dtheta < 0 then dtheta = dtheta + 2 * math.pi end

    local pts = {}
    for s = 1, steps do
        local t = theta1 + dtheta * (s / steps)
        local ct, st = math.cos(t), math.sin(t)
        pts[#pts + 1] = cx + rx * cosPhi * ct - ry * sinPhi * st
        pts[#pts + 1] = cy + rx * sinPhi * ct + ry * cosPhi * st
    end
    return pts
end

--- walks the path once into a flat point list normalized to 0..1, plus the
-- point count of each subpath (a mark like GitHub's is one outline with
-- holes, and the stencil needs to know where each ends)
---@param d string # path data
---@param svgSize number # the viewBox edge, e.g. 24
---@param steps integer # segments per curve
---@return number[] # points; flat x, y pairs in 0..1
---@return integer[] # subpaths; point count per subpath
local function flatten(d, svgSize, steps)
    local tokens = tokenize(d)
    local pts, idx = {}, 1
    local subpaths, subpathPoints = {}, 0
    --- the next numeric token, consuming it
    local function num() local t = tokens[idx]; idx = idx + 1; return t.num end

    local cx, cy, sx, sy, cmd = 0, 0, 0, 0, nil
    --- records a point, normalized out of viewBox space
    local function add(x, y)
        pts[#pts + 1] = x / svgSize
        pts[#pts + 1] = y / svgSize
        subpathPoints = subpathPoints + 1
    end

    --- closes the subpath in progress and begins counting a new one
    local function startSubpath()
        if subpathPoints > 0 then subpaths[#subpaths + 1] = subpathPoints end
        subpathPoints = 0
    end
    --- flattens a cubic bezier from the current point into `steps` segments
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
    --- flattens an elliptical arc from the current point to (ex, ey)
    local function arc(rx, ry, rotDeg, largeArc, sweep, ex, ey)
        local raw = arcPoints(cx, cy, rx, ry, rotDeg, largeArc, sweep, ex, ey, steps)
        for i = 1, #raw, 2 do add(raw[i], raw[i + 1]) end
        cx, cy = ex, ey
    end

    while idx <= #tokens do
        if tokens[idx].cmd then cmd = tokens[idx].cmd; idx = idx + 1 end
        if cmd == "M" then
            startSubpath()
            cx, cy = num(), num(); sx, sy = cx, cy; add(cx, cy); cmd = "L"
        elseif cmd == "m" then
            startSubpath()
            cx, cy = cx + num(), cy + num(); sx, sy = cx, cy; add(cx, cy); cmd = "l"
        elseif cmd == "L" then
            cx, cy = num(), num(); add(cx, cy)
        elseif cmd == "l" then
            cx, cy = cx + num(), cy + num(); add(cx, cy)
        elseif cmd == "C" then
            cubic(num(), num(), num(), num(), num(), num())
        elseif cmd == "c" then
            cubic(cx + num(), cy + num(), cx + num(), cy + num(), cx + num(), cy + num())
        elseif cmd == "A" then
            arc(num(), num(), num(), num() ~= 0, num() ~= 0, num(), num())
        elseif cmd == "a" then
            local rx, ry, rot = num(), num(), num()
            local largeArc, sweep = num() ~= 0, num() ~= 0
            arc(rx, ry, rot, largeArc, sweep, cx + num(), cy + num())
        elseif cmd == "z" or cmd == "Z" then
            cx, cy = sx, sy
        else
            error("svgPath: unsupported path command '" .. tostring(cmd) .. "'")
        end
    end
    startSubpath() -- flush whatever subpath the loop ended mid-way through
    return pts, subpaths
end

SvgPath.flatten = flatten

return SvgPath
