--- The reduced-motion switch every ambient UI animation checks, so the
-- Options toggle has a single place to reach.

local Motion = {}

Motion.reduced = false

---@param reduced boolean
function Motion.setReduced(reduced)
    Motion.reduced = reduced
end

return Motion
