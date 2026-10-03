--- Builders for rows that apply live and save at once.
-- `key` is the settings field and the i18n label suffix.

local I18n = require("core.i18n")
local Settings = require("core.settings")
local UI = require("ui")

local Rows = {}

---@param key string
---@return fun(): string
local function label(key)
    return function() return I18n.t("options." .. key) end
end

--- first index `matches` accepts, else 1
---@param list any[]
---@param matches fun(entry: any): boolean
---@return integer
function Rows.indexWhere(list, matches)
    for i, entry in ipairs(list) do
        if matches(entry) then return i end
    end
    return 1
end

---@param id string
---@return fun(entry: table): boolean
function Rows.byId(id)
    return function(entry) return entry.id == id end
end

--- applies live while dragging, saves on release
---@param screen table # the Options state
---@param key string
---@param apply fun(value: number)
---@param blip boolean # click on release; music previews itself
---@return table
function Rows.volumeSlider(screen, key, apply, blip)
    return UI.Slider.new{
        label = label(key),
        value = screen.settings[key],
        step = 0.1,
        onChange = function(value)
            screen.settings[key] = value
            apply(value)
        end,
        onRelease = function()
            if blip then UI.Sfx.select() end
            Settings.save(screen.settings)
        end,
    }
end

---@param screen table
---@param key string
---@param value any
---@param sideEffect? fun(value: any)
local function commit(screen, key, value, sideEffect)
    UI.Sfx.select()
    screen.settings[key] = value
    if sideEffect then sideEffect(value) end
    Settings.save(screen.settings)
end

---@param screen table
---@param key string
---@param sideEffect? fun(value: boolean)
---@return table
function Rows.toggle(screen, key, sideEffect)
    return UI.Toggle.new{
        label = label(key),
        value = screen.settings[key],
        onChange = function(value) commit(screen, key, value, sideEffect) end,
    }
end

--- picks a plain value from a list
---@param screen table
---@param key string
---@param options any[]
---@param format fun(option: any): string
---@param sideEffect? fun(value: any)
---@return table
function Rows.selector(screen, key, options, format, sideEffect)
    return UI.Selector.new{
        label = label(key),
        options = options,
        format = format,
        onChange = function(value) commit(screen, key, value, sideEffect) end,
    }
end

--- picks from { id } entries, saving the id
---@param screen table
---@param key string
---@param options table[]
---@param apply fun(id: string)
---@param relayout? boolean # the choice changes text sizes
---@return table
function Rows.idSelector(screen, key, options, apply, relayout)
    return UI.Selector.new{
        label = label(key),
        options = options,
        format = function(entry) return I18n.t("options." .. key .. "Name." .. entry.id) end,
        onChange = function(entry)
            commit(screen, key, entry.id, apply)
            if relayout then screen:layout() end
        end,
    }
end

--- points a plain-value selector at a saved value
---@param selector table
---@param value any
function Rows.selectValue(selector, value)
    selector.index = Rows.indexWhere(selector.options, function(v) return v == value end)
end

---@param key string
---@return fun(): string
function Rows.section(key)
    return function() return I18n.t("options.section." .. key) end
end

return Rows
