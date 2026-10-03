--- The first-run "share anonymous stats?" prompt.

local I18n = require("core.i18n")
local Stats = require("services.stats")
local UI = require("ui")

local Consent = {}

---@param settings table
---@return table # a UI.Dialog
function Consent.new(settings)
    local dialog
    local function answer(enabled)
        Stats.setConsent(settings, enabled)
        dialog:close()
    end

    -- Decline first, so a reflexive Enter can't opt in
    dialog = UI.Dialog.new{
        title = function() return I18n.t("menu.statsConsent.title") end,
        message = function() return I18n.t("menu.statsConsent.message") end,
        buttons = {
            { label = function() return I18n.t("menu.statsConsent.decline") end,
              onSelect = function() answer(false) end },
            { label = function() return I18n.t("menu.statsConsent.accept") end,
              onSelect = function() answer(true) end },
        },
        onCancel = function() answer(false) end, -- dismissing is declining
    }
    dialog:onFocusChanged(UI.Sfx.focus)
    return dialog
end

---@param settings table
---@return boolean
function Consent.needed(settings)
    return not settings.statsConsentAsked
end

return Consent
