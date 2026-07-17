-- src/states/loading.lua
-- First state shown on launch. Runs a queue of load tasks (one per frame so
-- the progress bar animates), then switches to the main menu. Real projects
-- put actual asset creation (images, audio, fonts) inside each task's `run`.

local StateManager = require "lib.stateManager"
local Assets = require "lib.assets"

local Loading = {}

function Loading:enter()
    -- Each task does one real piece of setup. Add heavier loads here later.
    self.tasks = {
        { label = "Preparing fonts", run = function()
            Assets.set("titleFont", love.graphics.newFont(72))
            Assets.set("headingFont", love.graphics.newFont(40))
            Assets.set("menuFont", love.graphics.newFont(28))
        end },
        { label = "Loading settings", run = function()
            Assets.set("settings", { fullscreen = false, vsync = 0, volume = 0.8 })
        end },
        { label = "Warming up", run = function() end },
    }

    self.index = 0
    self.progress = 0
    self.elapsed = 0
    self.minDuration = 1.2 -- keep the bar on screen at least this long
    self.finished = false
    self.label = nil
end

function Loading:update(dt)
    self.elapsed = self.elapsed + dt

    -- Process one task per frame so progress is visible even though each task
    -- here is fast. Swap to a time-budgeted loop for genuinely heavy loads.
    if self.index < #self.tasks then
        self.index = self.index + 1
        local task = self.tasks[self.index]
        self.label = task.label
        if task.run then task.run() end
    end

    self.progress = self.index / #self.tasks

    if not self.finished and self.progress >= 1 and self.elapsed >= self.minDuration then
        self.finished = true
        StateManager.switch("mainMenu")
    end
end

function Loading:draw()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()

    love.graphics.printf("Loading", 0, h * 0.4, w, "center")

    local barW, barH = w * 0.5, 24
    local barX, barY = (w - barW) / 2, h * 0.5

    love.graphics.setColor(0.2, 0.2, 0.2, 1)
    love.graphics.rectangle("fill", barX, barY, barW, barH, 6, 6)

    love.graphics.setColor(0.3, 0.7, 1.0, 1)
    love.graphics.rectangle("fill", barX, barY, barW * self.progress, barH, 6, 6)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("line", barX, barY, barW, barH, 6, 6)

    if self.label then
        love.graphics.printf(self.label .. "...", 0, barY + barH + 12, w, "center")
    end
end

return Loading
