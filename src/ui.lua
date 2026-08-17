-- src/ui.lua
-- Namespace for the game's UI toolkit. Usage:
--
--   local UI = require "ui"
--   UI.Theme.colors.accent
--   UI.Button.new{ label = "Play", onSelect = ... }
--
-- (A .lua file rather than src/ui/init.lua because these modules resolve
-- through plain package.path, which may not include ?/init.lua.)

return {
    Theme       = require "ui.core.theme",
    Cursor      = require "ui.core.cursor",
    Sfx         = require "ui.core.sfx",
    Glyph       = require "ui.icons.glyph",
    Widget      = require "ui.widgets.widget",
    FocusGroup  = require "ui.widgets.focusGroup",
    Dialog      = require "ui.widgets.dialog",
    Button      = require "ui.widgets.button",
    Toggle      = require "ui.widgets.toggle",
    Slider      = require "ui.widgets.slider",
    Selector    = require "ui.widgets.selector",
    TabBar      = require "ui.widgets.tabBar",
    ProgressBar = require "ui.widgets.progressBar",
    Label       = require "ui.text.label",
}
