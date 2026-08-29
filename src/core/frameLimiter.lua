local FrameLimiter = {
    uncapped = false,
}

function FrameLimiter.setUncapped(value)
    FrameLimiter.uncapped = value
end

return FrameLimiter