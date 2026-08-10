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
    Theme       = require "ui.theme",
    Cursor      = require "ui.cursor",
    Sfx         = require "ui.sfx",
    Glyph       = require "ui.glyph",
    Widget      = require "ui.widget",
    FocusGroup  = require "ui.focusGroup",
    Dialog      = require "ui.dialog",
    Button      = require "ui.button",
    Toggle      = require "ui.toggle",
    Slider      = require "ui.slider",
    Selector    = require "ui.selector",
    TabBar      = require "ui.tabBar",
    ProgressBar = require "ui.progressBar",
    Label       = require "ui.label",
}
