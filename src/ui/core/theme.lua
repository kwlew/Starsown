local Color = require("utils.math").Color
local Colors = require("ui.core.theme.colors")
local Metrics = require("ui.core.theme.metrics")
local Font = require("ui.core.theme.font")
local Glow = require("ui.core.theme.glow")
local Chrome = require("ui.core.theme.chrome")
local Util = require("ui.core.theme.util")

local Theme = {
    Colors = Colors,
    Metrics = Metrics,
    Font = Font,
    Glow = Glow,
    Chrome = Chrome,
    Util = Util,
}

-- colours
Theme.DEFAULT = Colors.DEFAULT
Theme.colors = Colors.colors
Theme.fixedColors = Colors.fixed
Theme.available = Colors.available
Theme.setTheme = Colors.setTheme
Theme.titleGradient = Colors.titleGradient
Theme.setColor = Colors.set
Theme.lerp = Color.lerp

-- scale
Theme.metrics = Metrics.metrics
Theme.px = Metrics.px

--- recomputes the UI scale and metrics for a window height, dropping every
-- font and glow built at the old scale when it actually changed. Call on resize.
---@param height? number # defaults to the current window height
---@return boolean changed
function Theme.rescale(height)
    if not Metrics.rescale(height or love.graphics.getHeight()) then return false end
    Font.clearCache()
    Glow.clearCache()
    return true
end

-- fonts
Theme.DEFAULT_UI_FONT = Font.DEFAULT_UI_FONT
Theme.font = Font.get
Theme.fontSized = Font.sized
Theme.fontFor = Font.resolve
Theme.fontRoles = Font.roles
Theme.uiFontFamilies = Font.uiFamilies
Theme.currentUiFontFamily = Font.currentUiFamily
Theme.setUiFontFamily = Font.setUiFamily
Theme.capHeight = Font.capHeight
Theme.centerY = Font.centerY
Theme.pushFont = Font.push
Theme.popFont = Font.pop

-- drawing
Theme.pulse = Glow.pulse
Theme.glowRect = Glow.rect
Theme.rowChrome = Chrome.row
Theme.panel = Chrome.panel

-- helpers
Theme.pointIn = Util.pointIn
Theme.approach = Util.approach
Theme.resolveLabel = Util.resolveLabel

-- Theme.current and Theme.scale change at runtime, so they're read through
-- from their owners rather than copied
local live = {
    current = function() return Colors.current end,
    scale = function() return Metrics.scale end,
}

return setmetatable(Theme, {
    __index = function(_, key)
        local read = live[key]
        if read then return read() end
    end,
})
