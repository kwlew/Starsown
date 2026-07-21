-- src/states/loading.lua
-- First state shown on launch. Runs a queue of load tasks (one per frame so
-- the progress bar animates), applies saved settings, then switches to the
-- main menu. Real projects put actual asset creation (images, audio, fonts)
-- inside each task's `run`.

local StateManager = require "lib.stateManager"
local Assets = require "lib.assets"
local Settings = require "lib.settings"
local UI = require "lib.ui"
local I18n = require "lib.i18n"

local DOT_INTERVAL = 0.3 -- seconds between "..." animation steps

local Loading = {}

-- Runs a task's work, isolating failures so one bad asset doesn't abort the
-- whole boot — the error is logged and loading continues.
local function runTask(task)
    if not task.run then return end
    local ok, err = pcall(task.run)
    if not ok then
        print(("[loading] task '%s' failed: %s"):format(tostring(task.label), tostring(err)))
    end
end

function Loading:enter()
    love.graphics.setBackgroundColor(UI.Theme.colors.bg)

    self.tasks = {
        { label = I18n.t("loading.task.interface"), run = function()
            -- Warm the theme's font cache so later screens don't hitch.
            UI.Theme.font("title")
            UI.Theme.font("heading")
            UI.Theme.font("body")
            UI.Theme.font("small")
        end },
        { label = I18n.t("loading.task.settings"), run = function()
            local settings = Settings.load()
            Settings.apply(settings)
            Assets.set("settings", settings)
        end },
        { label = I18n.t("loading.task.warmup"), run = function() end },
    }

    self.bar = UI.ProgressBar.new{}
    self.index = 0
    self.elapsed = 0
    self.minDuration = 1.2 -- keep the screen up at least this long
    self.finished = false
    self.label = nil

    self.dotTimer = 0
    self.dotCount = 0
end

function Loading:update(dt)
    -- Clamp dt so a single stalled frame (a heavy task, a window-mode
    -- change) can't fast-forward past minDuration and skip the screen.
    dt = math.min(dt, 0.1)
    self.elapsed = self.elapsed + dt

    -- Advance one task per frame so each step is visible. Swap to a
    -- time-budgeted loop here for genuinely heavy loads.
    if self.index < #self.tasks then
        self.index = self.index + 1
        local task = self.tasks[self.index]
        self.label = task.label
        runTask(task)
    end

    self.bar:setProgress(self.index / #self.tasks)
    self.bar:update(dt)

    -- Animated trailing dots on the heading.
    self.dotTimer = self.dotTimer + dt
    if self.dotTimer >= DOT_INTERVAL then
        self.dotTimer = self.dotTimer - DOT_INTERVAL
        self.dotCount = (self.dotCount + 1) % 4
    end

    -- Leave only once every task is done, the bar has visually filled, and
    -- the minimum on-screen time has elapsed.
    if not self.finished and self.bar:isComplete() and self.elapsed >= self.minDuration then
        self.finished = true
        StateManager.switch("mainMenu")
    end
end

function Loading:draw()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()

    UI.Label.draw{
        text = I18n.t("loading.title") .. string.rep(".", self.dotCount),
        y = h * 0.38,
        font = UI.Theme.font("heading"),
    }

    local barW, barH = w * 0.5, 26
    self.bar:draw((w - barW) / 2, h * 0.52, barW, barH)

    if self.label then
        UI.Label.draw{
            text = self.label,
            y = h * 0.52 + barH + 16,
            font = UI.Theme.font("small"),
            color = UI.Theme.colors.textDim,
        }
    end
end

return Loading
