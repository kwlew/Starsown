--- The authored palettes, in the order the options menu lists them. Each
-- names only a handful of colours; palette.lua derives every other role.
-- Any role may also be overridden outright by naming it here.
--
-- Fields: id, accent, accentAlt?, neutralHue?, tint? (a scalar, or per-role
-- multipliers with an optional `default`), title? (three gradient stops),
-- plus any role name.

return {
    {
        id        = "default",
        accent    = { 0.34, 0.68, 0.96 },
        accentAlt = { 0.62, 0.42, 0.98 },
        tint      = 0.70,
        title     = { { 0.25, 0.60, 1.00 }, { 0.85, 0.92, 1.00 }, { 0.62, 0.40, 1.00 } },
    },
    {
        id         = "carbon",
        accent     = { 0.32, 0.33, 0.36 },
        accentAlt  = { 0.90, 0.90, 0.92 },
        neutralHue = { 0.55, 0.62, 0.78 },
        tint       = 0.70,
        glow       = { 0.75, 0.78, 0.85 },
        accentDim  = { 0.52, 0.55, 0.62 },
        title      = { { 0.42, 0.44, 0.48 }, { 0.85, 0.92, 1.00 }, { 0.34, 0.36, 0.40 } },
    },
    {
        id        = "amethyst",
        accent    = { 0.52, 0.18, 0.72 },
        accentAlt = { 0.82, 0.26, 0.66 },
        tint      = 0.75,
    },
    {
        id        = "emerald",
        accent    = { 0.30, 0.82, 0.56 },
        accentAlt = { 0.36, 0.76, 0.96 },
        tint      = 0.70,
        title     = { { 0.20, 0.90, 0.55 }, { 0.88, 1.00, 0.92 }, { 0.30, 0.78, 1.00 } },
    },
    {
        id        = "lavender",
        accent    = { 0.68, 0.38, 0.95 },
        accentAlt = { 0.95, 0.46, 0.82 },
        tint      = 0.75,
        title     = { { 0.62, 0.25, 1.00 }, { 0.95, 0.86, 1.00 }, { 1.00, 0.40, 0.85 } },
    },
    {
        id        = "topaz",
        accent    = { 0.95, 0.80, 0.32 },
        accentAlt = { 0.96, 0.52, 0.30 },
        tint      = { default = 0.70, text = 0.25, textMuted = 0.30, textDim = 0.40 },
        warning   = { 0.98, 0.45, 0.08 }, -- topaz's own accent is gold; a pale warning would vanish into it
        danger    = { 0.95, 0.10, 0.14 },
        title     = { { 1.00, 0.90, 0.30 }, { 1.00, 0.95, 0.82 }, { 1.00, 0.50, 0.30 } },
    },
    {
        id        = "ember",
        accent    = { 0.96, 0.58, 0.22 },
        accentAlt = { 0.96, 0.36, 0.44 },
        tint      = 0.70,
        warning   = { 1.00, 0.88, 0.48 },
        danger    = { 1.00, 0.26, 0.30 },
        title     = { { 1.00, 0.72, 0.25 }, { 1.00, 0.95, 0.82 }, { 1.00, 0.38, 0.32 } },
    },
    {
        id        = "slate",
        accent    = { 0.70, 0.78, 0.92 },
        accentAlt = { 0.52, 0.60, 0.76 },
        tint      = 0.40,
    },
    {
        id        = "ruby",
        accent    = { 0.80, 0.18, 0.20 },
        accentAlt = { 0.96, 0.52, 0.32 },
        tint      = 0.5,
        danger    = { 0.98, 0.32, 0.30 },
        title     = { { 0.75, 0.10, 0.10 }, { 1.00, 0.90, 0.85 }, { 0.75, 0.20, 0.10 } },
    },
    {
        id        = "diamond",
        accent    = { 0.45, 0.86, 0.94 },
        accentAlt = { 0.68, 0.94, 1.00 },
        tint      = 0.45,
    },
    {
        id        = "lapis",
        accent    = { 0.30, 0.48, 0.92 },
        accentAlt = { 0.42, 0.70, 1.00 },
        tint      = 0.45,
    },
    {
        id        = "rose",
        accent    = { 0.76, 0.22, 0.44 },
        accentAlt = { 0.62, 0.30, 0.80 },
        tint      = 0.45,
        danger    = { 0.98, 0.28, 0.26 }, -- rose's own accent already reads close to red; danger needs its own hue
    },
    {
        id        = "peridot",
        accent    = { 0.55, 0.81, 0.35 },
        accentAlt = { 0.95, 0.85, 0.35 },
        tint      = 0.55,
    },
    {
        id        = "indigo",
        accent    = { 0.35, 0.27, 0.83 },
        accentAlt = { 0.93, 0.37, 0.93 },
        tint      = 0.55,
    },
}
