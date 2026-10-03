--- Recording a player's answer to a sharing question.

local Settings = require("core.settings")

local Consent = {}

--- saves the answer, and that it was asked
---@param settings table
---@param shareKey string # e.g. "shareStats"
---@param askedKey string # e.g. "statsConsentAsked"
---@param enabled boolean
function Consent.record(settings, shareKey, askedKey, enabled)
    settings[shareKey] = enabled
    settings[askedKey] = true
    Settings.save(settings)
end

--- whether this question still needs asking
---@param settings table
---@param askedKey string
---@return boolean
function Consent.pending(settings, askedKey)
    return not settings[askedKey]
end

return Consent
