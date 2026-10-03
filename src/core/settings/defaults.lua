--- Every setting's default, and the values some may take.

local Defaults = {}

Defaults.values = {
    windowMode = "windowed",
    vsync = 0,
    uncapFps = false,
    msaa = 4,
    volume = 0.8,
    musicVolume = 0.8,
    sfxVolume = 0.8,
    res_x = 1280,
    res_y = 720,
    display = 1,
    language = "en",
    theme = "default",
    titleFont = "acme",
    uiFont = "oxanium",
    customCursor = true,
    customCursorColor = "theme",
    customCursorSize = 3,
    customCursorOutlineWidth = 0.5,
    customCursorHoverOutlineWidth = 1,
    customCursorClickGrowth = 3,
    reducedMotion = false,
    showNebula = true,
    showStars = true,
    shareStats = false,
    statsConsentAsked = false,
    discordConsentAsked = false,
}

Defaults.WINDOW_MODES = { "windowed", "borderless", "exclusive" }
Defaults.MSAA_LEVELS = { 0, 2, 4, 8, 16 }

-- the keys only Apply in Options may change
Defaults.GRAPHICS_KEYS = { "res_x", "res_y", "display", "windowMode", "vsync", "msaa" }

return Defaults
