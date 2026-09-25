--- Options > Interface: language, theme, fonts, cursor, motion and stats
-- sharing. Everything here applies live and saves immediately.

local Assets = require "core.assets"
local Settings = require "core.settings"
local UI = require "ui"
local I18n = require "core.i18n"
local Stats = require "services.stats"
local GameTitle = require "ui.text.gameTitle"
local Rows = require "states.options.rows"

-- design-space pixel values (see Theme.px) offered for the custom cursor's tuning knobs
local CURSOR_SIZES = { 2, 3, 4, 5, 6, 7, 8 }
local CURSOR_OUTLINE_WIDTHS = { 0, 0.5, 1, 1.5, 2, 2.5, 3 }
local CURSOR_HOVER_OUTLINE_WIDTHS = { 0.5, 1, 1.5, 2, 2.5, 3 }
local CURSOR_CLICK_GROWTHS = { 1, 2, 3, 4, 5, 6, 8 }

---@param value number
---@return string
local function pxFormat(value)
    if value == math.floor(value) then return string.format("%dpx", value) end
    return string.format("%.1fpx", value)
end

--- switches the UI palette and rebuilds the one thing that can't just re-read
-- it: the nebula stamps accent colors into its canvases at bake time, so it
-- keeps the old theme's hues until re-baked. Shared instance from Assets, so
-- this also recolors the main menu's copy.
---@param id string
local function applyTheme(id)
    if not UI.Theme.setTheme(id) then return end

    local nebula = Assets.get("nebula")
    if nebula and nebula:isBaked() then nebula:bake() end
end

local InterfaceTab = {}
InterfaceTab.__index = InterfaceTab

--- a selector over a list of { id } entries whose choice is saved as that id
---@param screen table
---@param key string # i18n label, description key and settings field
---@param options table[]
---@param apply fun(id: string)
---@param relayout? boolean # the choice changes text metrics, so row heights must be re-measured
---@return table
local function idSelector(screen, key, options, apply, relayout)
    local selector = UI.Selector.new{
        label = function() return I18n.t("options." .. key) end,
        options = options,
        format = function(entry) return I18n.t("options." .. key .. "Name." .. entry.id) end,
        onChange = function(entry)
            UI.Sfx.select()
            screen.settings[key] = entry.id
            apply(entry.id)
            if relayout then screen:layout() end
            Settings.save(screen.settings)
        end,
    }
    selector.descKey = "options.desc." .. key
    return selector
end

---@param screen table # the Options state
---@return table
function InterfaceTab.new(screen)
    local self = setmetatable({ name = "interface" }, InterfaceTab)

    self.language = UI.Selector.new{
        label = function() return I18n.t("options.language") end,
        options = I18n.available(),
        format = function(entry) return entry.name end,
        onChange = function(entry)
            UI.Sfx.select()
            screen.settings.language = entry.code
            I18n.setLanguage(entry.code)
            screen:layout()
            Settings.save(screen.settings)
        end,
    }
    self.language.descKey = "options.desc.language"

    self.theme = idSelector(screen, "theme", UI.Theme.available(), applyTheme)
    self.titleFont = idSelector(screen, "titleFont", GameTitle.available(), GameTitle.setFont)
    self.uiFont = idSelector(screen, "uiFont", UI.Theme.uiFontFamilies(), UI.Theme.setUiFontFamily, true)

    self.cursorSize = Rows.settingSelector(screen, "customCursorSize", CURSOR_SIZES, pxFormat,
        UI.Cursor.setSize)
    self.cursorOutlineWidth = Rows.settingSelector(screen, "customCursorOutlineWidth",
        CURSOR_OUTLINE_WIDTHS, pxFormat, UI.Cursor.setOutlineWidth)
    self.cursorHoverOutlineWidth = Rows.settingSelector(screen, "customCursorHoverOutlineWidth",
        CURSOR_HOVER_OUTLINE_WIDTHS, pxFormat, UI.Cursor.setHoverOutlineWidth)
    self.cursorClickGrowth = Rows.settingSelector(screen, "customCursorClickGrowth",
        CURSOR_CLICK_GROWTHS, pxFormat, UI.Cursor.setClickGrowth)
    self.cursorTuning = { self.cursorSize, self.cursorOutlineWidth,
        self.cursorHoverOutlineWidth, self.cursorClickGrowth }

    self.customCursor = Rows.settingToggle(screen, "customCursor", function(value)
        UI.Cursor.setEnabled(value)
        for _, widget in ipairs(self.cursorTuning) do widget.enabled = value end
        screen.group:refresh()
    end)

    self.reducedMotion = Rows.settingToggle(screen, "reducedMotion", UI.Motion.setReduced)
    self.shareStats = Rows.settingToggle(screen, "shareStats", Stats.setEnabled)

    self.language.section = function() return I18n.t("options.section.appearance") end
    self.customCursor.section = function() return I18n.t("options.section.cursor") end
    self.reducedMotion.section = function() return I18n.t("options.section.accessibility") end
    self.shareStats.section = function() return I18n.t("options.section.privacy") end

    self.widgets = {
        self.language,
        self.theme, UI.Preview.newTheme{},
        self.titleFont, UI.Preview.newTitleFont{},
        self.uiFont, UI.Preview.newUiFont{},
        self.customCursor, self.cursorSize, self.cursorOutlineWidth,
        self.cursorHoverOutlineWidth, self.cursorClickGrowth,
        self.reducedMotion,
        self.shareStats,
    }
    return self
end

--- points every row back at the saved values; called on each visit
---@param settings table
function InterfaceTab:sync(settings)
    local function byId(id) return function(e) return e.id == id end end
    self.language.index = Rows.indexWhere(I18n.available(), function(e) return e.code == settings.language end)
    self.theme.index = Rows.indexWhere(UI.Theme.available(), byId(UI.Theme.current))
    self.titleFont.index = Rows.indexWhere(GameTitle.available(), byId(GameTitle.current))
    self.uiFont.index = Rows.indexWhere(UI.Theme.uiFontFamilies(), byId(UI.Theme.currentUiFontFamily()))

    self.customCursor.value = settings.customCursor
    Rows.selectValue(self.cursorSize, settings.customCursorSize)
    Rows.selectValue(self.cursorOutlineWidth, settings.customCursorOutlineWidth)
    Rows.selectValue(self.cursorHoverOutlineWidth, settings.customCursorHoverOutlineWidth)
    Rows.selectValue(self.cursorClickGrowth, settings.customCursorClickGrowth)
    for _, widget in ipairs(self.cursorTuning) do widget.enabled = settings.customCursor end

    self.reducedMotion.value = settings.reducedMotion
    self.shareStats.value = settings.shareStats
end

return InterfaceTab
