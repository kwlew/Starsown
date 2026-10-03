--- Window size limits that never exceed the desktop.

local Limits = { width = 800, height = 600 }

---@param display integer
---@return number|nil w
---@return number|nil h
local function desktop(display)
    if not love.window then return nil end -- love.conf runs before the window module
    local w, h = love.window.getDesktopDimensions(display)
    if not w or w <= 0 or not h or h <= 0 then return nil end
    return w, h
end

---@param display integer
---@return number w
---@return number h
function Limits.minimum(display)
    local w, h = desktop(display)
    if not w then return Limits.width, Limits.height end
    return math.min(Limits.width, w), math.min(Limits.height, h)
end

--- clamps a windowed size between minimum and desktop
---@param w number
---@param h number
---@param display integer
---@return number w
---@return number h
function Limits.windowSize(w, h, display)
    local minW, minH = Limits.minimum(display)
    local deskW, deskH = desktop(display)
    return math.max(minW, math.min(w, deskW or w)), math.max(minH, math.min(h, deskH or h))
end

return Limits
