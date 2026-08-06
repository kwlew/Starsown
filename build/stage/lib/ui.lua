-- lib/ui.lua
-- Namespace for the game's UI toolkit. Usage:
--
--   local UI = require "lib.ui"
--   UI.Theme.colors.accent
--   UI.Button.new{ label = "Play", onSelect = ... }
--
-- (A .lua file rather than lib/ui/init.lua because these modules resolve
-- through plain package.path, which may not include ?/init.lua.)

return {
    Theme       = require "lib.ui.theme",
    Cursor      = require "lib.ui.cursor",
    Sfx         = require "lib.ui.sfx",
    Glyph       = require "lib.ui.glyph",
    Widget      = require "lib.ui.widget",
    FocusGroup  = require "lib.ui.focusGroup",
    Dialog      = require "lib.ui.dialog",
    Button      = require "lib.ui.button",
    Toggle      = require "lib.ui.toggle",
    Slider      = require "lib.ui.slider",
    Selector    = require "lib.ui.selector",
    TabBar      = require "lib.ui.tabBar",
    ProgressBar = require "lib.ui.progressBar",
    Label       = require "lib.ui.label",
}
