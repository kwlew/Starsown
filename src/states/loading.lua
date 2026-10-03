--- Boot screen: runs the load, then opens the menu.

local Ease = require("utils.ease")
local I18n = require("core.i18n")
local Math = require("utils.math")
local Mixer = require("core.audio.mixer")
local Runner = require("states.loading.runner")
local StateManager = require("core.state.manager")
local Tasks = require("states.loading.tasks")
local UI = require("ui")
local VersionLabel = require("states.loading.versionLabel")

local Loading = {}

local WORK_BUDGET = 0.004  -- s of loading per frame
local MIN_FILL_TIME = 1.25 -- s; a presentation beat
local OUTRO_TIME = 0.9
local FURNITURE_FADE = 0.45 -- of the outro
local SKY_FADE_SPEED = 3.0
local DOT_INTERVAL = 0.5
local MAX_ANIMATION_DT = 0.1

local TITLE_SCALE = 1.3
local TITLE_Y_RATIO = 0.30
local HEADING_Y_RATIO = 0.52
local BAR_Y_RATIO = 0.64
local BAR_W_RATIO = 0.5
local BAR_H = 26
local CAPTION_GAP = 8
local FAILURE_GAP = 14

---@param previousName string|nil
---@param settings table # read at boot
function Loading:enter(previousName, settings)
    self.runner = Runner.new(Tasks.build(settings, function(stars, nebula)
        self.stars, self.nebula = stars, nebula
    end))
    self.phase = "loading"
    self.elapsed, self.outro = 0, 0
    self.dotTimer, self.dotCount = 0, 0
    self.stars, self.nebula = nil, nil

    self.bar = UI.ProgressBar.new{ showPercent = false, fillSpeed = 12 }
    self.title = UI.GameTitle.build()
    self.version = VersionLabel.new()
end

---@param w number
---@param h number
---@param rescaled boolean
function Loading:resize(w, h, rescaled)
    self.title = UI.GameTitle.build()
    if rescaled then self.version:rebuild() else self.version:layout() end
end

---@param layer table|nil
---@param dt number
local function fadeIn(layer, dt)
    if not layer then return end
    layer:update(dt)
    layer.alpha = Math.clamp01(layer.alpha + dt * SKY_FADE_SPEED)
end

---@param dt number
function Loading:update(dt)
    local animationDt = math.min(dt, MAX_ANIMATION_DT)
    self.elapsed = self.elapsed + dt

    if self.phase == "loading" then
        self.runner:run(WORK_BUDGET)
        self.bar:setProgress(math.min(self.runner:progress(), self.elapsed / MIN_FILL_TIME))
        if self.runner:isDone() and self.bar:isComplete() then self.phase = "outro" end
    else
        self.outro = self.outro + animationDt
        if self.outro >= OUTRO_TIME then
            Mixer.stopAll()
            return StateManager.switch("mainMenu")
        end
    end

    self.bar:update(animationDt)
    self.title:update(animationDt)
    fadeIn(self.nebula, animationDt)
    fadeIn(self.stars, animationDt)

    self.dotTimer = self.dotTimer + animationDt
    if self.dotTimer >= DOT_INTERVAL then
        self.dotTimer = self.dotTimer - DOT_INTERVAL
        self.dotCount = (self.dotCount + 1) % 4
    end
end

---@return number # 0..1
function Loading:outroProgress()
    return self.phase == "outro" and math.min(1, self.outro / OUTRO_TIME) or 0
end

--- the word stays put while the dots grow beside it
---@param y number
---@param alpha number
function Loading:drawHeading(y, alpha)
    local font = UI.Theme.font("heading")
    local text = I18n.t("loading.title")
    local width = font:getWidth(text)
    local x = (love.graphics.getWidth() - width) / 2
    UI.Label.draw{ text = text, x = x, y = y, width = width, align = "left", font = font, alpha = alpha }
    UI.Label.draw{ text = string.rep(".", self.dotCount), x = x + width, y = y,
        width = font:getWidth("..."), align = "left", font = font, alpha = alpha }
end

---@param alpha number
function Loading:drawProgress(alpha)
    local w, h = love.graphics.getDimensions()
    local barW, barH = w * BAR_W_RATIO, UI.Theme.px(BAR_H)
    local barX, barY = (w - barW) / 2, h * BAR_Y_RATIO

    local font = UI.Theme.font("small")
    local captionY = barY - font:getHeight() - UI.Theme.px(CAPTION_GAP)
    UI.Theme.pushFont(font)
    UI.Theme.setColor(UI.Theme.colors.textDim, alpha)
    love.graphics.printf(self.runner:label() or "", barX, captionY, barW, "left")
    love.graphics.printf(Math.round(self.bar.shown * 100) .. "%", barX, captionY, barW, "right")
    UI.Theme.popFont()

    self.bar.alpha = alpha
    self.bar:draw(barX, barY, barW, barH)

    local failures = #self.runner.failures
    if failures > 0 then
        UI.Label.draw{ text = I18n.t("loading.failed", { n = failures }),
            y = barY + barH + UI.Theme.px(FAILURE_GAP), font = font,
            color = UI.Theme.colors.warning, alpha = alpha }
    end
end

function Loading:draw()
    local h = love.graphics.getHeight()
    local outro = self:outroProgress()
    local ease = Ease.outCubic(outro)

    if self.nebula then self.nebula:draw() end
    if self.stars then self.stars:draw() end

    local startY, endY = h * TITLE_Y_RATIO, h * UI.GameTitle.MENU_Y_RATIO
    UI.GameTitle.drawScaled(self.title, startY + (endY - startY) * ease, TITLE_SCALE + (1 - TITLE_SCALE) * ease)
    self.version:draw(ease)

    local alpha = 1 - math.min(1, outro / FURNITURE_FADE)
    if alpha <= 0 then return end
    self:drawHeading(h * HEADING_Y_RATIO, alpha)
    self:drawProgress(alpha)
end

return Loading
