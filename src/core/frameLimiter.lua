local FrameLimiter = {
    uncapped = false,
}

---@param value boolean # true lets the game run past the display's refresh rate
function FrameLimiter.setUncapped(value)
    FrameLimiter.uncapped = value
end

return FrameLimiter