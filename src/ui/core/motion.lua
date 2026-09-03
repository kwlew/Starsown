--- Controls reduced-motion behavior for interface animations.

local Motion = {}

Motion.reduced = false

--- the one switch every ambient animation checks, so the Options toggle has a
-- single place to reach
---@param reduced boolean
function Motion.setReduced(reduced)
    Motion.reduced = reduced
end

return Motion
