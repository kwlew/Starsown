--- The Graphics tab's prompts: revert countdown, unapplied changes, errors.

local I18n = require("core.i18n")
local UI = require("ui")

local Dialogs = {}

local REVERT_SECONDS = 10

---@param settings table
---@return string # what the driver actually granted
local function grantedSummary(settings)
    local msaa = settings.msaa == 0 and I18n.t("options.msaaOff") or settings.msaa .. "x"
    local vsync = I18n.t(settings.vsync == 0 and "options.state.off" or "options.state.on")
    return I18n.t("options.adjustedGraphics") .. "\n"
        .. I18n.t("options.displayOption", { n = settings.display }) .. " · "
        .. I18n.t("options.windowMode." .. settings.windowMode) .. " · "
        .. settings.res_x .. "×" .. settings.res_y .. "\n"
        .. I18n.t("options.msaa") .. ": " .. msaa .. " · VSync: " .. vsync
end

---@param key string
---@return fun(): string
local function text(key)
    return function() return I18n.t(key) end
end

---@param tab table # the GraphicsTab
---@return table revert
function Dialogs.revert(tab)
    return UI.Dialog.new{
        title = text("dialog.revert.title"),
        fontRole = "help",
        message = function(dialog)
            local message = I18n.t("dialog.revert.message", { n = math.max(0, math.ceil(dialog:remaining() or 0)) })
            if tab.previewAdjusted then message = message .. "\n\n" .. grantedSummary(tab.screen.settings) end
            return message
        end,
        timeout = REVERT_SECONDS,
        onTimeout = function() tab:revert() end,
        onCancel = function() tab:revert() end,
        buttons = {
            { label = text("dialog.revert.revert"), danger = true, onSelect = function() tab:revert() end },
            { label = text("dialog.revert.keep"), onSelect = function() tab:keep() end },
        },
    }
end

---@param tab table
---@return table unapplied
function Dialogs.unapplied(tab)
    local dialog
    dialog = UI.Dialog.new{
        title = text("dialog.unapplied.title"),
        message = text("dialog.unapplied.message"),
        onCancel = function() dialog:close() end,
        buttons = {
            { label = text("dialog.unapplied.discard"), danger = true, onSelect = function()
                dialog:close()
                tab:discardAndLeave()
            end },
            { label = text("dialog.unapplied.apply"), onSelect = function()
                dialog:close()
                tab:applyAndLeave()
            end },
        },
    }
    return dialog
end

---@param tab table
---@return table error
function Dialogs.error(tab)
    local dialog
    dialog = UI.Dialog.new{
        title = text("options.errorTitle"),
        message = function() return I18n.t("options.error." .. (tab.error or "failed")) end,
        fontRole = "help",
        buttons = { { label = text("dialog.close"), onSelect = function() dialog:close() end } },
    }
    return dialog
end

---@param tab table
---@return table dialogs # { revert, unapplied, error, all = { ... } }
function Dialogs.build(tab)
    local set = { revert = Dialogs.revert(tab), unapplied = Dialogs.unapplied(tab), error = Dialogs.error(tab) }
    set.all = { set.revert, set.unapplied, set.error }
    for _, dialog in ipairs(set.all) do dialog:onFocusChanged(UI.Sfx.focus) end
    return set
end

return Dialogs
