-- namespace: local UI = require "ui"; UI.Theme.colors.accent, UI.Button.new{...}
-- .lua not ui/init.lua because package.path here has no ?/init.lua

return {
    Theme       = require "ui.core.theme",
    Cursor      = require "ui.core.cursor",
    Motion      = require "ui.core.motion",
    Sfx         = require "ui.core.sfx",
    Music       = require "ui.core.music",
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
