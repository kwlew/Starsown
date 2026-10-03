--- The line under the stats: error, freshness, or emptiness.

local Format = require("utils.format")
local I18n = require("core.i18n")
local StatsService = require("services.stats")

local Status = {}

local GRACE_SECONDS = 8 -- before "still waiting" sounds alarming

---@return string|nil
local function updatedText()
    if not StatsService.lastUpdated then return nil end
    return I18n.t("stats.updated", { t = Format.duration(love.timer.getTime() - StatsService.lastUpdated) })
end

--- which line to show, and which button goes with it
---@param hasValues boolean
---@return string|nil text
---@return "copy"|"enable"|nil action
---@return boolean isError
function Status.current(hasValues)
    local err = StatsService.enabled and StatsService.lastError()
    if err then
        local key = err.code == "ST-NOHTTPS" and "stats.error.unsupported" or "stats.error.generic"
        return I18n.t(key) .. "\n" .. I18n.t("stats.error.code", { code = err.code }), "copy", true
    end
    if hasValues then return updatedText(), nil, false end
    if not StatsService.enabled then return I18n.t("stats.sharingOff"), "enable", false end
    local elapsed = StatsService.startedAt and love.timer.getTime() - StatsService.startedAt or 0
    return I18n.t(elapsed < GRACE_SECONDS and "stats.loading" or "stats.waiting"), nil, false
end

return Status
