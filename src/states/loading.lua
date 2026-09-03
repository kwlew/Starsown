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
local GameTitle = require "ui.text.gameTitle"
local TextFactory = require "ui.text.textFactory"
local Globals = require "globals"

local DOT_INTERVAL = 0.5 -- seconds between "..." animation steps
local OUTRO_TIME = 0.9  -- length of the hand-off animation
local MIN_FILL_TIME = 1.25 -- intentional presentation beat; not a claim that work is still running
local WORK_BUDGET = 0.004  -- seconds of cooperative loading work allowed per update

local FURNITURE_FADE = 0.45
local SKY_FADE_SPEED = 3.0 -- alpha/sec the sky (nebula + stars) fades up

local TITLE_SCALE = 1.3
local TITLE_Y_RATIO = 0.30

local VERSION_BIG_SIZE = 64 -- design-space font px, native raster size (see buildBigVersionLabel)
local VERSION_BIG_Y_RATIO = 0.85
local VERSION_PAD = 12 -- must match mainMenu.lua's CORNER_PAD

local HEADING_Y_RATIO = 0.52
local BAR_Y_RATIO = 0.64
local BAR_W_RATIO = 0.5
local BAR_H = 26 -- design-space px

local Loading = {}

--- nil until the task that builds it has run, so both callers can fire from the first frame
---@param layer table|nil
---@param dt number
local function fadeInSky(layer, dt)
    if not layer then return end
    layer:update(dt)
    layer.alpha = Math.clamp01(layer.alpha + dt * SKY_FADE_SPEED)
end

--- the small corner pose, matching what the main menu draws
---@return table # a TextFactory
local function buildVersionLabel()
    return TextFactory:new{
        text = "v" .. Globals.game.version,
        font = UI.Theme.font("small"),
        color = UI.Theme.colors.textDim,
    }
end

--- big loading-screen pose of the same label: same typeface as buildVersionLabel,
-- rasterized at its own native size rather than stretched up from the small
-- role's tiny glyph texture, so it draws crisp -- drawVersionScaled only ever
-- scales it *down* toward the small pose, never up
---@return table # a TextFactory
local function buildBigVersionLabel()
    return TextFactory:new{
        text = "v" .. Globals.game.version,
        font = UI.Theme.fontSized("small", VERSION_BIG_SIZE),
        color = UI.Theme.colors.text,
    }
end

local CLIPS = {
    { "assets/audio/bg/ambientmain_0.ogg", "mainMenuBG", "stream" },
    { "assets/audio/bg/mainMenuBG2.flac", "mainMenuBG2", "stream" },
    { "assets/audio/bg/mainMenuBG3_spooky.flac", "mainMenuBG3", "stream" },
    { "assets/audio/sfx/explosions/star_explosion.wav", "starExplosion" },
    { "assets/audio/sfx/explosions/star_explosion2.wav", "starExplosion2" },
    { "assets/audio/sfx/explosions/star_explosion3.wav", "starExplosion3" },
    { "assets/audio/sfx/explosions/golden_star_explosion.wav", "goldenStarExplosion" },
    { "assets/audio/sfx/menu/menuButton3.wav", "menuButton3" },
    { "assets/audio/sfx/menu/menuButton4.wav", "menuButton4" },
    { "assets/audio/sfx/menu/menuBeep.mp3", "menuBeep" },
}

local STATES = {
    { "mainMenu", "states.mainMenu" },
    { "play", "states.play" },
    { "options", "states.options" },
    { "stats", "states.stats" },
    { "achievements", "states.achievements" },
}

--- the load itself, as weighted tasks. Each `run` gets a `yield(fraction)` to
-- report progress and hand the frame back, and a `warn(detail)` to record a
-- failure without taking the load down -- which is what keeps a missing
-- font/clip/locale a warning rather than a crash.
---@return table[]
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
                local settings = self.startupSettings or Settings.load()
                Settings.apply(settings)
                Assets.set("settings", settings)
            end,
        },
        {
            label = I18n.t("loading.task.screens"),
            weight = 2,
            run = function(yield)
                for i, spec in ipairs(STATES) do
                    StateManager.register(spec[1], require(spec[2]))
                    yield(i / #STATES)
                end
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

                local settings = Assets.get("settings")
                local nebula = Particles.Nebula.new{ alpha = 0, enabled = settings.showNebula }
                Assets.set("nebula", nebula)
                self.nebula = nebula
                if settings.showNebula then
                    nebula:beginBake()
                    local done, progress
                    repeat
                        done, progress = nebula:bakeStep()
                        yield(0.5 + progress * 0.5)
                    until done
                else
                    yield(1)
                end
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

---@param previousName string|nil
---@param settings? table # the settings conf.lua already read, so they aren't loaded twice
function Loading:enter(previousName, settings)
    love.graphics.setBackgroundColor(UI.Theme.colors.bg)

    self.startupSettings = settings
    self.metrics = { tasks = {}, maxStep = 0, maxWorkFrame = 0 }
    self.enteredAt = love.timer.getTime()
    self.firstDrawAt = nil
    self.loadFinishedAt = nil

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
    self.versionSmall = buildVersionLabel()
    self.versionBig = buildBigVersionLabel()
    self:layoutVersion()
    self.stars = nil
    self.nebula = nil

    self.dotTimer = 0
    self.dotCount = 0

    --- handed to every task: report progress 0..1 and give the frame back
    self.yield = function(fraction) return coroutine.yield(fraction) end
    --- handed to every task: record a failure and carry on
    self.warn = function(detail) self:recordFailure(self.label, detail) end
end

--- big centered pose vs. mainMenu's exact small corner pose, so drawVersionScaled
-- only has to ease between the two endpoints computed here; versionEndScale is
-- derived from real font metrics rather than a guessed ratio, so the big font
-- (native size VERSION_BIG_SIZE) lands as close as possible to the small
-- font's actual rendered size at ease = 1
--- computes both version poses; call on resize
function Loading:layoutVersion()
    local w, h = love.graphics.getDimensions()
    local bigFont, smallFont = self.versionBig.font, self.versionSmall.font
    local bigWidth, bigHeight = bigFont:getWidth(self.versionBig.text), bigFont:getHeight()
    local smallWidth, smallHeight = smallFont:getWidth(self.versionSmall.text), smallFont:getHeight()
    local pad = UI.Theme.px(VERSION_PAD)

    self.versionEndScale = smallHeight / bigHeight
    self.versionBigX = (w - bigWidth) / 2
    self.versionBigY = h * VERSION_BIG_Y_RATIO
    self.versionMenuX = w - smallWidth - pad
    self.versionMenuY = h - pad - smallHeight
end

---@param w number
---@param h number
---@param rescaled boolean # the UI scale changed, so the version labels need re-rasterizing
function Loading:resize(w, h, rescaled)
    self.title = GameTitle.build()
    if rescaled then
        self.versionSmall = buildVersionLabel()
        self.versionBig = buildBigVersionLabel()
    end
    self:layoutVersion()
end

--- a failed task is counted and logged; the screen shows how many, and the
-- load carries on
---@param label string|nil
---@param detail any
function Loading:recordFailure(label, detail)
    self.failures[#self.failures + 1] = detail
    print(("[loading] task '%s' failed: %s"):format(tostring(label), tostring(detail)))
end

---@return number # 0..1, weighted by task and including the running task's own partial
function Loading:progress()
    if self.totalWeight == 0 then return 1 end
    local task = self.tasks[self.index]
    local partial = task and (task.weight or 1) * self.partial or 0
    return (self.doneWeight + partial) / self.totalWeight
end

---@return boolean # every task finished
function Loading:isLoaded()
    return self.index > #self.tasks
end

--- resumes the current task's coroutine once, advancing to the next when it
-- finishes. A task that errors is recorded and skipped rather than propagated.
function Loading:step()
    local task = self.tasks[self.index]
    if not task then return end

    if not self.coroutine then
        self.label = task.label
        self.partial = 0
        self.coroutine = coroutine.create(task.run)
        task.workTime = 0
    end

    local started = love.timer.getTime()
    local ok, value = coroutine.resume(self.coroutine, self.yield, self.warn)
    local duration = love.timer.getTime() - started
    task.workTime = task.workTime + duration
    self.metrics.maxStep = math.max(self.metrics.maxStep, duration)
    if not ok then
        self:recordFailure(task.label, value)
    elseif type(value) == "number" then
        self.partial = Math.clamp01(value)
    end

    if coroutine.status(self.coroutine) == "dead" then
        self.metrics.tasks[#self.metrics.tasks + 1] = {
            label = task.label,
            seconds = task.workTime,
        }
        self.doneWeight = self.doneWeight + (task.weight or 1)
        self.index = self.index + 1
        self.coroutine = nil
        self.partial = 0
    end
end

--- runs tasks until they're done or the frame's work budget is spent, so the
-- screen keeps animating throughout. The bar is also held to MIN_FILL_TIME --
-- a presentation beat, not a claim that work is still running.
---@param dt number
function Loading:update(dt)
    local animationDt = math.min(dt, 0.1)
    self.elapsed = self.elapsed + dt

    if self.phase == "loading" then
        local workStarted = love.timer.getTime()
        repeat
            self:step()
        until self:isLoaded() or love.timer.getTime() - workStarted >= WORK_BUDGET
        local workDuration = love.timer.getTime() - workStarted
        self.metrics.maxWorkFrame = math.max(self.metrics.maxWorkFrame, workDuration)
        if self:isLoaded() and not self.loadFinishedAt then
            self.loadFinishedAt = love.timer.getTime()
            self.metrics.loadSeconds = self.loadFinishedAt - self.enteredAt
        end

        self.bar:setProgress(math.min(self:progress(), self.elapsed / MIN_FILL_TIME))

        if self:isLoaded() and self.bar:isComplete() then
            self.phase = "outro"
        end
    else
        self.outro = self.outro + animationDt
        if self.outro >= OUTRO_TIME then
            Audio.stopAll()
            StateManager.switch("mainMenu")
            return
        end
    end

    self.bar:update(animationDt)

    fadeInSky(self.nebula, animationDt)
    fadeInSky(self.stars, animationDt)

    self.dotTimer = self.dotTimer + animationDt
    if self.dotTimer >= DOT_INTERVAL then
        self.dotTimer = self.dotTimer - DOT_INTERVAL
        self.dotCount = (self.dotCount + 1) % 4
    end
end

---@return number # 0..1, 0 until the outro begins
function Loading:outroProgress()
    if self.phase ~= "outro" then return 0 end
    return math.min(1, self.outro / OUTRO_TIME)
end

--- "Loading" stays put and the dots grow to its right; drawn as two pieces
-- because centering the whole string re-centers it on every dot and makes
-- the word itself twitch left/right
---@param text string
---@param dots string
---@param y number
---@param alpha number
local function drawHeading(text, dots, y, alpha)
    local font = UI.Theme.font("heading")
    local width = font:getWidth(text)
    local x = (love.graphics.getWidth() - width) / 2

    UI.Label.draw{ text = text, x = x, y = y, width = width, align = "left",
                   font = font, alpha = alpha }
    UI.Label.draw{ text = dots, x = x + width, y = y, width = font:getWidth("..."),
                   align = "left", font = font, alpha = alpha }
end

--- eases the version label between its two poses, so the hand-off to the main
-- menu lands on an identical frame
---@param version table # a TextFactory
---@param bigX number # loading pose
---@param bigY number
---@param menuX number # main-menu pose
---@param menuY number
---@param endScale number # scale at the menu pose
---@param ease number # 0..1
local function drawVersionScaled(version, bigX, bigY, menuX, menuY, endScale, ease)
    local scale = 1 + (endScale - 1) * ease
    local x = bigX + (menuX - bigX) * ease
    local y = bigY + (menuY - bigY) * ease

    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.scale(scale, scale)
    love.graphics.setColor(UI.Theme.lerp(UI.Theme.colors.text, UI.Theme.colors.textDim, ease))
    love.graphics.draw(version.textObject, 0, 0)
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)
end

--- sky, title and version throughout; the heading, bar and any failure count
-- fade out during the outro
function Loading:draw()
    if not self.firstDrawAt then
        self.firstDrawAt = love.timer.getTime()
        self.metrics.firstDrawSeconds = self.firstDrawAt - self.enteredAt
    end
    local w, h = love.graphics.getDimensions()
    local outro = self:outroProgress()
    local alpha = 1 - math.min(1, outro / FURNITURE_FADE)

    if self.nebula then self.nebula:draw() end
    if self.stars then self.stars:draw() end

    local ease = Ease.outCubic(outro)
    local titleY = h * TITLE_Y_RATIO + (h * GameTitle.MENU_Y_RATIO - h * TITLE_Y_RATIO) * ease
    GameTitle.drawScaled(self.title, titleY, TITLE_SCALE + (1 - TITLE_SCALE) * ease)

    drawVersionScaled(self.versionBig, self.versionBigX, self.versionBigY,
                       self.versionMenuX, self.versionMenuY, self.versionEndScale, ease)

    if alpha <= 0 then return end

    drawHeading(I18n.t("loading.title"), string.rep(".", self.dotCount), h * HEADING_Y_RATIO, alpha)

    local barW = w * BAR_W_RATIO
    local barH = UI.Theme.px(BAR_H)
    local barX, barY = (w - barW) / 2, h * BAR_Y_RATIO

    local font = UI.Theme.font("small")
    local captionY = barY - font:getHeight() - UI.Theme.px(8)
    UI.Theme.pushFont(font)
    UI.Theme.setColor(UI.Theme.colors.textDim, alpha)
    love.graphics.printf(self.label or "", barX, captionY, barW, "left")
    love.graphics.printf(Math.round(self.bar.shown * 100) .. "%", barX, captionY, barW, "right")
    UI.Theme.popFont()

    self.bar.alpha = alpha
    self.bar:draw(barX, barY, barW, barH)

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
