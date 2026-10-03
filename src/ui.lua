--- One require for the whole UI: local UI = require("ui"); UI.Button.new{...}
-- A .lua file rather than ui/init.lua because package.path here has no ?/init.lua.

return {
    -- core
    Theme       = require("ui.core.theme"),
    Cursor      = require("ui.core.cursor"),
    Motion      = require("ui.core.motion"),
    Sfx         = require("ui.core.sfx"),

    -- input, layout, animation
    Bindings    = require("ui.input.bindings"),
    RowLayout   = require("ui.layout.rowLayout"),
    Intro       = require("ui.animation.intro"),

    -- icons
    Icon        = require("ui.icons.icon"),
    Glyph       = require("ui.icons.glyph"),
    IconTexture = require("ui.icons.iconTexture"),
    Marks       = require("ui.icons.marks"),
    Chevron     = require("ui.icons.chevron"),

    -- text
    Label       = require("ui.text.label"),
    Hint        = require("ui.text.hint"),
    TextCache   = require("ui.text.textCache"),
    TextFactory = require("ui.text.textFactory"),
    GameTitle   = require("ui.text.gameTitle"),
    Splash      = require("ui.text.splash"),

    -- widgets
    Widget      = require("ui.widgets.widget"),
    FocusGroup  = require("ui.widgets.focusGroup"),
    Button      = require("ui.widgets.button"),
    Toggle      = require("ui.widgets.toggle"),
    Slider      = require("ui.widgets.slider"),
    Selector    = require("ui.widgets.selector"),
    TabBar      = require("ui.widgets.tabBar"),
    Menu        = require("ui.widgets.menu"),
    Dialog      = require("ui.widgets.dialog"),
    ScrollArea  = require("ui.widgets.scrollArea"),
    IconLink    = require("ui.widgets.iconLink"),
    ProgressBar = require("ui.widgets.progressBar"),
    Swatches    = require("ui.widgets.preview.swatches"),
    FontSample  = require("ui.widgets.preview.fontSample"),
}
