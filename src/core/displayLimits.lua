-- Logical window dimensions. Smaller desktops use their available size;
-- never force an oversized window onto a display that cannot contain it.
local Limits = { width = 800, height = 600 }

function Limits.minimum(display)
    -- love.conf runs before the window module is initialized.
    if not love.window then return Limits.width, Limits.height end
    local w, h = love.window.getDesktopDimensions(display)
    if not w or w <= 0 or not h or h <= 0 then return Limits.width, Limits.height end
    return math.min(Limits.width, w), math.min(Limits.height, h)
end

function Limits.windowSize(w, h, display)
    local minW, minH = Limits.minimum(display)
    if not love.window then return math.max(minW, w), math.max(minH, h) end
    local deskW, deskH = love.window.getDesktopDimensions(display)
    return math.max(minW, math.min(w, deskW and deskW > 0 and deskW or w)),
        math.max(minH, math.min(h, deskH and deskH > 0 and deskH or h))
end

return Limits
