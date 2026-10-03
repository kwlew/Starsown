--- What the loading screen loads, as weighted tasks.
-- Each run(yield, warn) reports progress via yield(0..1).

local Apply = require("core.settings.apply")
local Assets = require("core.assets")
local Backdrop = require("states.shared.backdrop")
local Clips = require("core.audio.clips")
local I18n = require("core.i18n")
local Library = require("core.audio.library")
local Registry = require("states.registry")
local StateManager = require("core.state.manager")
local UI = require("ui")

local Tasks = {}

---@param settings table
---@param onSky fun(stars: table, nebula: table) # so loading can fade them in
---@return table[]
function Tasks.build(settings, onSky)
    return {
        {
            label = I18n.t("loading.task.interface"),
            weight = 2,
            run = function(yield)
                local roles = UI.Theme.fontRoles()
                for i, role in ipairs(roles) do
                    UI.Theme.font(role)
                    yield(i / #roles)
                end
            end,
        },
        {
            label = I18n.t("loading.task.settings"),
            weight = 1,
            run = function()
                Apply.graphics(settings)
                Apply.audio(settings)
                Assets.set("settings", settings)
            end,
        },
        {
            label = I18n.t("loading.task.screens"),
            weight = 2,
            run = function(yield)
                for i, entry in ipairs(Registry) do
                    StateManager.register(entry[1], require(entry[2]))
                    yield(i / #Registry)
                end
            end,
        },
        {
            label = I18n.t("loading.task.world"),
            weight = 3,
            run = function(yield)
                local stars = Backdrop.newStars(settings, 0)
                local nebula = Backdrop.newNebula(settings, 0)
                onSky(stars, nebula)
                yield(0.5)
                if not settings.showNebula then return end
                nebula:beginBake()
                local done, progress
                repeat
                    done, progress = nebula:bakeStep()
                    yield(0.5 + progress * 0.5)
                until done
            end,
        },
        {
            label = I18n.t("loading.task.audio"),
            weight = 5,
            run = function(yield, warn)
                for i, clip in ipairs(Clips) do
                    if not Library.preload(clip[1], clip[2], clip[3]) then warn(clip[2]) end
                    yield(i / #Clips)
                end
            end,
        },
    }
end

return Tasks
