-- src/ui/core/motion.lua
-- Used to reduce motion in the main menu.

local Motion = {}

Motion.reduced = false

function Motion.setReduced(reduced)
    Motion.reduced = reduced
end

return Motion
