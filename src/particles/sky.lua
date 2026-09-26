--- The fixed design space the menu sky (Stars, Nebula) is authored in, and
-- the one transform both use to fit it to the window, so they stay aligned.

local Sky = {}

Sky.W, Sky.H = 1920, 1080

--- scales the sky uniformly until it covers the window, cropping the overflow
-- evenly off both sides; never stretches, never letterboxes
---@param w number
---@param h number
---@return number scale
---@return number x # screen position of the sky's top-left corner
---@return number y
function Sky.cover(w, h)
    local scale = math.max(w / Sky.W, h / Sky.H)
    return scale, (w - Sky.W * scale) / 2, (h - Sky.H * scale) / 2
end

return Sky
