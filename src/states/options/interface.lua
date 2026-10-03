--- Options > Interface: language, look, cursor, motion, privacy.

local Backdrop = require("states.shared.backdrop")
local I18n = require("core.i18n")
local Rows = require("states.options.rows")
local Settings = require("core.settings")
local Stats = require("services.stats")
local UI = require("ui")

local InterfaceTab = {}
InterfaceTab.__index = InterfaceTab

-- design px offered for the cursor's tuning
local CURSOR_SIZES = { 2, 3, 4, 5, 6, 7, 8 }
local CURSOR_OUTLINES = { 0, 0.5, 1, 1.5, 2, 2.5, 3 }
local CURSOR_HOVER_OUTLINES = { 0.5, 1, 1.5, 2, 2.5, 3 }
local CURSOR_CLICK_GROWTHS = { 1, 2, 3, 4, 5, 6, 8 }
local UI_FONT_SAMPLE = "AaBbCc 0123"

---@param value number
---@return string
local function px(value)
    if value == math.floor(value) then return ("%dpx"):format(value) end
    return ("%.1fpx"):format(value)
end

--- the nebula bakes colours in, so it rebakes
---@param id string
local function applyTheme(id)
    if UI.Theme.setTheme(id) then Backdrop.rebake() end
end

---@param screen table
---@return table
local function languageSelector(screen)
    return UI.Selector.new{
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
end

---@param screen table
function InterfaceTab:buildCursorRows(screen)
    local Cursor = UI.Cursor
    self.cursorColor = Rows.idSelector(screen, "customCursorColor", Cursor.pointerColors(), Cursor.setPointerColor)
    self.cursorSize = Rows.selector(screen, "customCursorSize", CURSOR_SIZES, px, Cursor.setSize)
    self.cursorOutline = Rows.selector(screen, "customCursorOutlineWidth", CURSOR_OUTLINES, px,
        Cursor.setOutlineWidth)
    self.cursorHoverOutline = Rows.selector(screen, "customCursorHoverOutlineWidth", CURSOR_HOVER_OUTLINES, px,
        Cursor.setHoverOutlineWidth)
    self.cursorClickGrowth = Rows.selector(screen, "customCursorClickGrowth", CURSOR_CLICK_GROWTHS, px,
        Cursor.setClickGrowth)
    self.cursorTuning = { self.cursorColor, self.cursorSize, self.cursorOutline,
        self.cursorHoverOutline, self.cursorClickGrowth }

    self.customCursor = Rows.toggle(screen, "customCursor", function(value)
        Cursor.setEnabled(value)
        self:syncCursorRows(screen.settings)
        screen.group:refresh()
    end)
end

---@param screen table # the Options state
---@return table
function InterfaceTab.new(screen)
    local self = setmetatable({ name = "interface" }, InterfaceTab)

    self.language = languageSelector(screen)
    self.theme = Rows.idSelector(screen, "theme", UI.Theme.available(), applyTheme)
    self.titleFont = Rows.idSelector(screen, "titleFont", UI.GameTitle.available(), UI.GameTitle.setFont)
    self.uiFont = Rows.idSelector(screen, "uiFont", UI.Theme.uiFontFamilies(), UI.Theme.setUiFontFamily, true)
    self:buildCursorRows(screen)
    self.reducedMotion = Rows.toggle(screen, "reducedMotion", UI.Motion.setReduced)
    self.shareStats = Rows.toggle(screen, "shareStats", Stats.setEnabled)

    self.language.section = Rows.section("appearance")
    self.customCursor.section = Rows.section("cursor")
    self.reducedMotion.section = Rows.section("accessibility")
    self.shareStats.section = Rows.section("privacy")

    self.widgets = {
        self.language,
        self.theme, UI.Swatches.new(),
        self.titleFont, UI.FontSample.new{ text = UI.GameTitle.TEXT, role = UI.GameTitle.currentRole },
        self.uiFont, UI.FontSample.new{ text = UI_FONT_SAMPLE, role = "button" },
        self.customCursor, self.cursorColor, self.cursorSize, self.cursorOutline,
        self.cursorHoverOutline, self.cursorClickGrowth,
        self.reducedMotion,
        self.shareStats,
    }
    return self
end

---@param settings table
function InterfaceTab:syncCursorRows(settings)
    for _, widget in ipairs(self.cursorTuning) do widget.enabled = settings.customCursor end
end

---@param settings table
function InterfaceTab:sync(settings)
    local byId = Rows.byId
    self.language.index = Rows.indexWhere(self.language.options, function(e) return e.code == settings.language end)
    self.theme.index = Rows.indexWhere(UI.Theme.available(), byId(UI.Theme.current))
    self.titleFont.index = Rows.indexWhere(UI.GameTitle.available(), byId(UI.GameTitle.current))
    self.uiFont.index = Rows.indexWhere(UI.Theme.uiFontFamilies(), byId(UI.Theme.currentUiFontFamily()))

    self.customCursor.value = settings.customCursor
    self.cursorColor.index = Rows.indexWhere(UI.Cursor.pointerColors(), byId(settings.customCursorColor))
    Rows.selectValue(self.cursorSize, settings.customCursorSize)
    Rows.selectValue(self.cursorOutline, settings.customCursorOutlineWidth)
    Rows.selectValue(self.cursorHoverOutline, settings.customCursorHoverOutlineWidth)
    Rows.selectValue(self.cursorClickGrowth, settings.customCursorClickGrowth)
    self:syncCursorRows(settings)

    self.reducedMotion.value = settings.reducedMotion
    self.shareStats.value = settings.shareStats
end

return InterfaceTab
