-- src/states/loading.lua
-- First state shown on launch. Runs a weighted queue of load tasks, then hands
-- off to the main menu.
--
-- Two things make the hand-off read as continuous rather than as a cut:
--   * the night sky is built here, drawn behind this screen, and passed to the
--     menu through Assets, so the background never pops in;
--   * the game title is drawn here too and eased into the menu's exact pose
--     during the outro, so the switch lands on an identical frame.
--
-- Tasks are coroutines. A task that calls yield() gives the frame back, so a
-- heavy one (five audio files to decode) moves the bar *while* it works instead
-- of stalling and then jumping. Weights make the bar reflect cost rather than
-- how many entries have been dequeued.

local StateManager = require "core.stateManager"
local Assets = require "core.assets"
local Settings = require "core.settings"
local UI = require "ui"
local I18n = require "core.i18n"
local Audio = require "core.audio"
local Audios = require "utils.audios"
local Particles = require "particles"
local Math = require "utils.math"
local Ease = require "utils.ease"
local GameTitle = require "ui.gameTitle"

local DOT_INTERVAL = 0.3 -- seconds between "..." animation steps
local OUTRO_TIME = 0.75  -- length of the hand-off animation
local MIN_FILL_TIME = 1.0

local FURNITURE_FADE = 0.45
local SKY_FADE_SPEED = 1.5 -- how fast the sky (nebula + stars) fades up, in alpha per second

-- Loading-screen pose of the title, eased to GameTitle.MENU_Y_RATIO at scale 1.
local TITLE_SCALE = 0.62
local TITLE_Y_RATIO = 0.30

-- Vertical anchors for the loading furniture, as fractions of window height.
local HEADING_Y_RATIO = 0.52
local BAR_Y_RATIO = 0.64
local BAR_W_RATIO = 0.5
local BAR_H = 26 -- design-space px

local Loading = {}

-- Ticks a background layer and eases its opacity up. nil until the task that
-- builds it has run, so both callers can fire from the first frame.
local function fadeInSky(layer, dt)
    if not layer then return end
    layer:update(dt)
    layer.alpha = Math.clamp01(layer.alpha + dt * SKY_FADE_SPEED)
end

local function buildVersionLabel()
    return TextFactory:new{
        text = "v" .. Globals.game.version,
        font = UI.Theme.font("small"),
        color = UI.Theme.colors.textDim,
    }
end

-- The audio the game needs.
local CLIPS = {
    { "assets/audio/bg/ambientmain_0.ogg", "mainMenuBG", "stream" },
    { "assets/audio/sfx/explosions/star_explosion.wav", "starExplosion" },
    { "assets/audio/sfx/explosions/golden_star_explosion.wav", "goldenStarExplosion" },
    { "assets/audio/sfx/menu/blipSelect.wav", "menuBlipSelect" },
    { "assets/audio/sfx/menu/blipSelect2.wav", "menuBlipSelect2" },
}

-- Each task gets (yield, warn):
--   yield(fraction) -- optional 0..1 progress within this task; ends the frame
--   warn(detail)    -- a non-fatal problem worth telling the player about
function Loading:buildTasks()
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
                local settings = Settings.load()
                Settings.apply(settings)
                Assets.set("settings", settings)
            end,
        },
        {
            label = I18n.t("loading.task.world"),
            weight = 3,
            run = function(yield)
                local stars = Particles.Stars.new{ alpha = 0 }
                stars:spawnStars()
                Assets.set("stars", stars)
                self.stars = stars
                yield(0.5)

                local nebula = Particles.Nebula.new{ alpha = 0 }
                nebula:bake()
                Assets.set("nebula", nebula)
                self.nebula = nebula
                yield(1)
            end,
        },
        {
            label = I18n.t("loading.task.audio"),
            weight = 5,
            run = function(yield, warn)
                for i, clip in ipairs(CLIPS) do
                    if not Audios.preload(clip[1], clip[2], clip[3]) then
                        warn(clip[2])
                    end
                    yield(i / #CLIPS)
                end
            end,
        },
    }
end

function Loading:enter()
    love.graphics.setBackgroundColor(UI.Theme.colors.bg)

    self.tasks = self:buildTasks()
    self.totalWeight = 0
    for _, task in ipairs(self.tasks) do
        self.totalWeight = self.totalWeight + (task.weight or 1)
    end

    self.index = 1
    self.doneWeight = 0
    self.partial = 0
    self.coroutine = nil
    self.label = nil
    self.failures = {}

    self.phase = "loading"
    self.elapsed = 0
    self.outro = 0

    self.bar = UI.ProgressBar.new{ showPercent = false, fillSpeed = 12 }
    self.title = GameTitle.build()
    self.stars = nil
    self.nebula = nil

    self.dotTimer = 0
    self.dotCount = 0

    self.yield = function(fraction) return coroutine.yield(fraction) end
    self.warn = function(detail) self:recordFailure(self.label, detail) end
end

function Loading:resize()
    self.title = GameTitle.build()
end

function Loading:recordFailure(label, detail)
    self.failures[#self.failures + 1] = detail
    print(("[loading] task '%s' failed: %s"):format(tostring(label), tostring(detail)))
end

function Loading:progress()
    if self.totalWeight == 0 then return 1 end
    local task = self.tasks[self.index]
    local partial = task and (task.weight or 1) * self.partial or 0
    return (self.doneWeight + partial) / self.totalWeight
end

function Loading:isLoaded()
    return self.index > #self.tasks
end

function Loading:step()
    local task = self.tasks[self.index]
    if not task then return end

    if not self.coroutine then
        self.label = task.label
        self.partial = 0
        self.coroutine = coroutine.create(task.run)
    end

    local ok, value = coroutine.resume(self.coroutine, self.yield, self.warn)
    if not ok then
        self:recordFailure(task.label, value)
    elseif type(value) == "number" then
        self.partial = Math.clamp01(value)
    end

    if coroutine.status(self.coroutine) == "dead" then
        self.doneWeight = self.doneWeight + (task.weight or 1)
        self.index = self.index + 1
        self.coroutine = nil
        self.partial = 0
    end
end

function Loading:update(dt)
    dt = math.min(dt, 0.1)
    self.elapsed = self.elapsed + dt

    if self.phase == "loading" then
        self:step()

        self.bar:setProgress(math.min(self:progress(), self.elapsed / MIN_FILL_TIME))

        -- Leave once every task is done and the bar has visually filled.
        if self:isLoaded() and self.bar:isComplete() then
            self.phase = "outro"
        end
    else
        self.outro = self.outro + dt
        if self.outro >= OUTRO_TIME then
            Audio.stopAll() -- stop any loading music before the menu starts
            StateManager.switch("mainMenu")
            return
        end
    end

    self.bar:update(dt)

    fadeInSky(self.nebula, dt)
    fadeInSky(self.stars, dt)

    -- Animated trailing dots on the heading.
    self.dotTimer = self.dotTimer + dt
    if self.dotTimer >= DOT_INTERVAL then
        self.dotTimer = self.dotTimer - DOT_INTERVAL
        self.dotCount = (self.dotCount + 1) % 4
    end
end

-- 0 while loading, ramping to 1 across the outro.
function Loading:outroProgress()
    if self.phase ~= "outro" then return 0 end
    return math.min(1, self.outro / OUTRO_TIME)
end

-- Heading: "Loading" stays put and the dots grow to its right. Drawn as two
-- pieces because centering the whole string re-centers it on every dot, which
-- makes the word itself twitch left and right a few px per step.
local function drawHeading(text, dots, y, alpha)
    local font = UI.Theme.font("heading")
    local width = font:getWidth(text)
    local x = (love.graphics.getWidth() - width) / 2

    UI.Label.draw{ text = text, x = x, y = y, width = width, align = "left",
                   font = font, alpha = alpha }
    UI.Label.draw{ text = dots, x = x + width, y = y, width = font:getWidth("..."),
                   align = "left", font = font, alpha = alpha }
end

function Loading:draw()
    local w, h = love.graphics.getDimensions()
    local outro = self:outroProgress()
    -- The furniture clears out first so the title finishes its travel against
    -- an otherwise empty screen.
    local alpha = 1 - math.min(1, outro / FURNITURE_FADE)

    -- Gas first: the stars are in front of it, not behind it.
    if self.nebula then self.nebula:draw() end
    if self.stars then self.stars:draw() end

    -- Title, easing from its own smaller pose into the menu's exact one.
    local ease = Ease.outCubic(outro)
    local titleY = h * TITLE_Y_RATIO + (h * GameTitle.MENU_Y_RATIO - h * TITLE_Y_RATIO) * ease
    GameTitle.drawScaled(self.title, titleY, TITLE_SCALE + (1 - TITLE_SCALE) * ease)

    if alpha <= 0 then return end

    drawHeading(I18n.t("loading.title"), string.rep(".", self.dotCount), h * HEADING_Y_RATIO, alpha)

    local barW = w * BAR_W_RATIO
    local barH = UI.Theme.px(BAR_H)
    local barX, barY = (w - barW) / 2, h * BAR_Y_RATIO

    -- Task label on the left, percentage on the right, both just above the bar,
    -- so the readout reads as a caption rather than text floating inside it.
    local font = UI.Theme.font("small")
    local captionY = barY - font:getHeight() - UI.Theme.px(8)
    UI.Theme.pushFont(font)
    UI.Theme.setColor(UI.Theme.colors.textDim, alpha)
    love.graphics.printf(self.label or "", barX, captionY, barW, "left")
    love.graphics.printf(Math.round(self.bar.shown * 100) .. "%", barX, captionY, barW, "right")
    UI.Theme.popFont()

    self.bar.alpha = alpha
    self.bar:draw(barX, barY, barW, barH)

    -- Non-fatal load failures: the game still boots, but silently missing audio
    -- would otherwise look like a bug in the game rather than in its install.
    if #self.failures > 0 then
        UI.Label.draw{
            text = I18n.t("loading.failed", { n = #self.failures }),
            y = barY + barH + UI.Theme.px(14),
            font = font,
            color = UI.Theme.colors.warning,
            alpha = alpha,
        }
    end
end

return Loading
