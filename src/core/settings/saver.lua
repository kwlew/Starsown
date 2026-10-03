--- Saving settings, holding back unconfirmed graphics changes.
-- During a preview, saves keep the last confirmed graphics.

local Defaults = require("core.settings.defaults")
local Store = require("core.settings.store")

local Saver = {}

local previews = setmetatable({}, { __mode = "k" }) -- settings -> confirmed graphics

---@param settings table
---@return table # the graphics keys only
function Saver.snapshot(settings)
    local snapshot = {}
    for _, key in ipairs(Defaults.GRAPHICS_KEYS) do snapshot[key] = settings[key] end
    return snapshot
end

---@param settings table
---@return boolean ok
---@return string? err
function Saver.save(settings)
    local baseline = previews[settings]
    if not baseline then return Store.write(settings) end

    local safe = {}
    for key, value in pairs(settings) do safe[key] = value end
    for key, value in pairs(baseline) do safe[key] = value end
    return Store.write(safe)
end

--- saves now, then holds these graphics as the confirmed ones
---@param settings table
---@return boolean ok
---@return string? err
function Saver.beginPreview(settings)
    if previews[settings] then return true end
    local ok, err = Saver.save(settings)
    if not ok then return false, err end
    previews[settings] = Saver.snapshot(settings)
    return true
end

--- keep: persist the previewed graphics; otherwise drop them
---@param settings table
---@param keep boolean
---@return boolean ok
---@return string? err
function Saver.endPreview(settings, keep)
    local baseline = previews[settings]
    previews[settings] = nil
    if keep then
        local ok, err = Saver.save(settings)
        if not ok then previews[settings] = baseline end
        return ok, err
    end
    if baseline then
        -- live values still differ: keep protecting the saved ones
        for _, key in ipairs(Defaults.GRAPHICS_KEYS) do
            if baseline[key] ~= settings[key] then
                previews[settings] = baseline
                break
            end
        end
    end
    return true
end

return Saver
