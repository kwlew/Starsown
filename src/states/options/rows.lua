--- Row builders shared by the Options tabs, for settings that apply live and
-- persist the moment they change. A row's i18n label, description key and
-- settings field are all `key` by construction. Graphics' Apply-gated rows
-- live in graphics.lua, since only that tab has a pending state.

local Settings = require "core.settings"
local UI = require "ui"
local I18n = require "core.i18n"

local Rows = {}

--- index of the first entry `matches` accepts, or 1 -- a saved value no
-- longer on offer (a resolution the monitor lost) falls back to the first option
---@param list any[]
---@param matches fun(entry: any): boolean
---@return integer
function Rows.indexWhere(list, matches)
    for i, entry in ipairs(list) do
        if matches(entry) then return i end
    end
    return 1
end

--- Music passes blip = false: it retunes live and is already its own preview,
-- so an sfx click on top would demo the wrong channel.
---@param screen table # the Options state; rows read its live `settings`
---@param key string
---@param apply fun(value: number) # applies the value live, throughout the drag
---@param blip boolean # play a click when the change settles
---@return table
function Rows.volumeSlider(screen, key, apply, blip)
    local slider = UI.Slider.new{
        label = function() return I18n.t("options." .. key) end,
        value = screen.settings[key],
        step = 0.1,
        onChange = function(value) -- live, fires throughout a drag
            screen.settings[key] = value
            apply(value)
        end,
        onRelease = function() -- final, fires when the change settles
            if blip then UI.Sfx.select() end
            Settings.save(screen.settings)
        end,
    }
    slider.descKey = "options.desc." .. key
    return slider
end

---@param screen table
---@param key string
---@param sideEffect? fun(value: boolean) # anything beyond the settings write, e.g. UI.Cursor.setEnabled
---@return table
function Rows.settingToggle(screen, key, sideEffect)
    local toggle = UI.Toggle.new{
        label = function() return I18n.t("options." .. key) end,
        value = screen.settings[key],
        onChange = function(value)
            UI.Sfx.select()
            screen.settings[key] = value
            if sideEffect then sideEffect(value) end
            Settings.save(screen.settings)
        end,
    }
    toggle.descKey = "options.desc." .. key
    return toggle
end

--- a setting picked from a list of plain values rather than toggled
---@param screen table
---@param key string
---@param options any[]
---@param format fun(option: any): string
---@param sideEffect? fun(value: any) # anything beyond the settings write, e.g. UI.Cursor.setSize
---@return table
function Rows.settingSelector(screen, key, options, format, sideEffect)
    local selector = UI.Selector.new{
        label = function() return I18n.t("options." .. key) end,
        options = options,
        format = format,
        onChange = function(value)
            UI.Sfx.select()
            screen.settings[key] = value
            if sideEffect then sideEffect(value) end
            Settings.save(screen.settings)
        end,
    }
    selector.descKey = "options.desc." .. key
    return selector
end

--- points a row built by settingSelector back at the saved value
---@param selector table
---@param value any
function Rows.selectValue(selector, value)
    selector.index = Rows.indexWhere(selector.options, function(v) return v == value end)
end

return Rows
