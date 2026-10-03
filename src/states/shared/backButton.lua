--- The standard "Back" button.

local I18n = require("core.i18n")
local UI = require("ui")

---@param labelKey string
---@param onSelect fun()
---@return table # a UI.Button
return function(labelKey, onSelect)
    return UI.Button.new{
        label = function() return I18n.t(labelKey) end,
        icon = "back",
        onSelect = onSelect,
    }
end
