--- Pushes every setting into the system that uses it.

local FrameLimiter = require("core.frameLimiter")
local I18n = require("core.i18n")
local Mixer = require("core.audio.mixer")
local UI = require("ui")
local Window = require("core.settings.window")

local Apply = {}

---@param settings table
function Apply.interface(settings)
    I18n.setLanguage(settings.language)
    UI.Theme.setTheme(settings.theme)
    UI.GameTitle.setFont(settings.titleFont)
    UI.Theme.setUiFontFamily(settings.uiFont)
    UI.Motion.setReduced(settings.reducedMotion)
end

---@param settings table
function Apply.cursor(settings)
    local Cursor = UI.Cursor
    Cursor.setEnabled(settings.customCursor)
    Cursor.setPointerColor(settings.customCursorColor)
    Cursor.setSize(settings.customCursorSize)
    Cursor.setOutlineWidth(settings.customCursorOutlineWidth)
    Cursor.setHoverOutlineWidth(settings.customCursorHoverOutlineWidth)
    Cursor.setClickGrowth(settings.customCursorClickGrowth)
end

---@param settings table
function Apply.audio(settings)
    love.audio.setVolume(settings.volume)
    Mixer.setVolume("music", settings.musicVolume)
    Mixer.setVolume("sfx", settings.sfxVolume)
end

---@param settings table
function Apply.graphics(settings)
    Window.apply(settings)
    FrameLimiter.setUncapped(settings.uncapFps)
end

return Apply
