--- Settings: one entry point over defaults, file, saving and window.

local Defaults = require("core.settings.defaults")
local Saver = require("core.settings.saver")
local Store = require("core.settings.store")
local Window = require("core.settings.window")

local Settings = {}

Settings.defaults = Defaults.values
Settings.MSAA_LEVELS = Defaults.MSAA_LEVELS
Settings.WINDOW_MODES = Defaults.WINDOW_MODES

Settings.load = Store.read
Settings.save = Saver.save

Settings.graphicsSnapshot = Saver.snapshot
Settings.beginGraphicsPreview = Saver.beginPreview
Settings.endGraphicsPreview = Saver.endPreview

Settings.applyGraphics = Window.apply
Settings.readGraphics = Window.read
Settings.trackWindowResize = Window.trackResize

return Settings
