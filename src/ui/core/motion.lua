-- Global "reduce motion" preference (options.reducedMotion): dampens the
-- purely decorative continuous animation elsewhere in the UI -- the
-- nebula's drift and breathing, the fixed sky's twinkle, the starfield's
-- speed and spawn rate, the splash text's pulse, and the title's chroma
-- cycling. Doesn't touch anything user-triggered (a star's pop burst) or
-- functional feedback (a focused widget's glow) -- see each module for its
-- own knob, this is just the flag they all read.
--
--   UI.Motion.setReduced(settings.reducedMotion) -- once at boot, and again
--                                                    whenever the Options toggle changes
--   if UI.Motion.reduced then ... end

local Motion = {}

Motion.reduced = false

function Motion.setReduced(reduced)
    Motion.reduced = reduced
end

return Motion
