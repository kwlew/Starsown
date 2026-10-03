--- Whether the main loop sleeps between frames.

local FrameLimiter = { uncapped = false }

---@param value boolean
function FrameLimiter.setUncapped(value)
    FrameLimiter.uncapped = value
end

return FrameLimiter
