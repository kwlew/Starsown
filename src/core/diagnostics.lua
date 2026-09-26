--- Where background services report what's wrong, so a failure can reach a
-- player as something they can report instead of a quiet "not working".
--
-- Each service owns one status line (shown in the F3 overlay) and at most
-- one current error: a short stable code players can quote (ST-HTTP-503,
-- DC-CLOSED-4000, ...) plus the technical detail behind it. A repeat of the
-- same error only bumps its count, so a service retrying every few seconds
-- logs once, not every attempt. Every change is printed and appended to
-- diagnostics.log in the save directory, which reportText() points players at.

local Diagnostics = {}

local LOG_FILE = "diagnostics.log"
local LOG_CAP = 64 * 1024 -- bytes; past this the oldest half is dropped
local DETAIL_CAP = 300 -- chars kept of a detail string, so one huge response body can't flood the log

local services = {} -- name -> { status, error = { code, detail, count, first, last } }
local order = {} -- service names in first-report order, for a stable overlay

---@param name string
---@return table
local function entry(name)
    local service = services[name]
    if not service then
        service = { status = nil, error = nil }
        services[name] = service
        order[#order + 1] = name
    end
    return service
end

---@param detail any
---@return string
local function clean(detail)
    local text = tostring(detail or ""):gsub("[%c]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if #text > DETAIL_CAP then text = text:sub(1, DETAIL_CAP) .. "..." end
    return text
end

--- appends one line, trimming the file first if it has grown past LOG_CAP.
-- Best effort: a log that can't be written must never take a service down.
---@param line string
local function log(line)
    print(line)
    if not (love and love.filesystem) then return end
    pcall(function()
        local info = love.filesystem.getInfo(LOG_FILE)
        if info and info.size and info.size > LOG_CAP then
            local old = love.filesystem.read(LOG_FILE) or ""
            local keep = old:sub(-math.floor(LOG_CAP / 2))
            keep = keep:gsub("^[^\n]*\n", "") -- don't start mid-line
            love.filesystem.write(LOG_FILE, keep)
        end
        love.filesystem.append(LOG_FILE, os.date("%Y-%m-%d %H:%M:%S ") .. line .. "\n")
    end)
end

--- the one-word state the overlay shows ("ok", "waiting for Discord", ...).
-- Only a change is logged.
---@param name string
---@param status string
function Diagnostics.setStatus(name, status)
    local service = entry(name)
    if service.status == status then return end
    service.status = status
    log(("[%s] status: %s"):format(name, status))
end

--- records a failure. The same code again only counts, so retry loops don't
-- spam the log; a new code replaces the old one and is logged.
---@param name string
---@param code string # short and stable, e.g. "ST-HTTP-503"
---@param detail? any # the technical why: an error message, a response snippet
function Diagnostics.report(name, code, detail)
    local service = entry(name)
    local now = os.time()
    local current = service.error
    detail = clean(detail)
    if current and current.code == code then
        current.count = current.count + 1
        current.last = now
        current.detail = detail ~= "" and detail or current.detail
        return
    end
    service.error = { code = code, detail = detail, count = 1, first = now, last = now }
    log(("[%s] error %s%s"):format(name, code, detail ~= "" and (": " .. detail) or ""))
end

--- the service is working again; logged only if there was an error to clear
---@param name string
function Diagnostics.clear(name)
    local service = entry(name)
    if not service.error then return end
    log(("[%s] recovered from %s (seen %d time%s)"):format(name, service.error.code,
        service.error.count, service.error.count == 1 and "" or "s"))
    service.error = nil
end

---@param name string
---@return table|nil # { code, detail, count, first, last }
function Diagnostics.error(name)
    return services[name] and services[name].error
end

---@param name string
---@return string|nil
function Diagnostics.status(name)
    return services[name] and services[name].status
end

---@return string[] # "name: status" plus the error code, one per service, for the F3 overlay
function Diagnostics.lines()
    local lines = {}
    for _, name in ipairs(order) do
        local service = services[name]
        local line = name .. ": " .. (service.status or "?")
        if service.error then line = line .. " [" .. service.error.code .. "]" end
        lines[#lines + 1] = line
    end
    return lines
end

--- everything a player should paste into a bug report about `name`:
-- version, platform, the error code, its detail, and where the full log is
---@param name string
---@return string
function Diagnostics.reportText(name)
    local Globals = require "globals"
    local major, minor, revision = love.getVersion()
    local lines = {
        ("%s %s | LOVE %d.%d.%d | %s"):format(Globals.game.name, Globals.game.version,
            major, minor, revision, love.system.getOS()),
        ("%s: %s"):format(name, Diagnostics.status(name) or "unknown"),
    }
    local err = Diagnostics.error(name)
    if err then
        lines[#lines + 1] = ("error: %s (seen %d time%s, first %s, last %s)"):format(err.code, err.count,
            err.count == 1 and "" or "s", os.date("%H:%M:%S", err.first), os.date("%H:%M:%S", err.last))
        if err.detail ~= "" then lines[#lines + 1] = "detail: " .. err.detail end
    end
    lines[#lines + 1] = "log: " .. love.filesystem.getSaveDirectory() .. "/" .. LOG_FILE
    return table.concat(lines, "\n")
end

return Diagnostics
