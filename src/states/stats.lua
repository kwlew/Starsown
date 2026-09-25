local StateManager = require "core.stateManager"
local UI = require "ui"
local I18n = require "core.i18n"
local Format = require "utils.format"
local StatsService = require "services.stats"
local Presence = require "services.presence"
local TextFactory = require "ui.text.textFactory"
local Assets = require "core.assets"
local Settings = require "core.settings"
local Ease = require "utils.ease"
local Math = require "utils.math"

local HEADING_Y_RATIO = 0.12
local LIST_Y_RATIO = 0.30
local ROW_H      = 34
local LIST_MAX_W = 420
local BACK_W     = 180
local STATUS_MAX_W = 460

local STATUS_GRACE_SECONDS = 8

local COPIED_SECONDS = 2 -- how long the copy button says "Copied" after a click

local INTRO_DURATION = 1.00
local INTRO_STAGGER = 0.05

local Stats = {}

local ROWS = {
    { labelKey = "stats.online",  get = function() return StatsService.online end },
    { labelKey = "stats.total",   get = function() return StatsService.stars end },
    { labelKey = "stats.golden",  get = function() return StatsService.golden end,
      tone = "gold" },
    { labelKey = "stats.rainbow", get = function() return StatsService.rainbow end,
      tone = "rainbow" },
}

local CHROMA_SPAN = 160
local CHROMA_SPEED = 0.5

local CHROMA_ROW
for i, row in ipairs(ROWS) do
    if row.tone == "rainbow" then CHROMA_ROW = i end
end

---@param n number|nil # nil reads as unavailable rather than 0 -- the counters
-- stay nil until the first successful response
---@return string
local function valueText(n)
    if not n then return I18n.t("stats.unavailable") end
    return Format.group(n)
end

--- keeps the rainbow row's TextFactory in step with the live value and the
-- current layout, rebuilding it only when the font actually changed
function Stats:syncChroma()
    local row = self.rows and self.rows[CHROMA_ROW]
    if not row then return end

    local font = UI.Theme.font("body")
    local text = valueText(ROWS[CHROMA_ROW].get())

    if not self.chroma or self.chroma.font ~= font then
        self.chroma = TextFactory:new{
            text = text,
            font = font,
            limit = row.w,
            align = "right",
            speed = CHROMA_SPEED,
            scale = UI.Theme.px(CHROMA_SPAN),
        }
    elseif self.chroma.text ~= text or self.chroma.limit ~= row.w then
        self.chroma.limit = row.w
        self.chroma.scale = UI.Theme.px(CHROMA_SPAN)
        self.chroma:setText(text)
    end
end

---@param previousName string|nil
---@param opts? table # { returnTo?: string }
function Stats:enter(previousName, opts)
    Presence.show("stats")
    self.returnTo = StateManager.returnTarget(previousName, opts, "stats")
    self.settings = Assets.get("settings") or Settings.load()

    self.mouseX, self.mouseY = love.mouse.getPosition()

    if not self.group then
        self.group = UI.FocusGroup.new()
        self.group.onFocusChanged = UI.Sfx.focus
    end

    if not self.backButton then
        self.backButton = UI.Button.new{
            label = function() return I18n.t("stats.back") end,
            onSelect = function() self:leave() end,
        }
        -- a direct shortcut for the exact problem "stats.sharingOff" names,
        -- rather than sending the player all the way to Options > Interface
        self.enableSharingButton = UI.Button.new{
            label = function() return I18n.t("stats.enableSharing") end,
            onSelect = function()
                UI.Sfx.select()
                StatsService.setConsent(self.settings, true)
                self:syncFocusWidgets()
                self:layout()
            end,
        }
        -- the error line names a code; this puts that code and everything
        -- behind it on the clipboard, ready to paste into a bug report
        self.copyButton = UI.Button.new{
            label = function()
                local copied = self.copiedAt and love.timer.getTime() - self.copiedAt < COPIED_SECONDS
                return I18n.t(copied and "stats.copied" or "stats.copyDetails")
            end,
            onSelect = function()
                UI.Sfx.select()
                love.system.setClipboardText(StatsService.reportText())
                self.copiedAt = love.timer.getTime()
            end,
        }
        self.rowAlpha = {}
    end
    self:syncFocusWidgets()

    self:layout()
    self:playIntro()
end

--- fades back to whichever screen opened this one
function Stats:leave()
    UI.Sfx.select()
    StateManager.fadeTo(self.returnTo)
end

--- centres the readout in a bordered card, keeping it clear of the heading
-- above and the hint line below however short the window is. Also
-- positions whatever sits below it -- the status line, and the button that
-- goes with it -- which needs the status line's own wrapped height, since
-- "sharing is off" and the error lines wrap on a narrow window.
function Stats:layout()
    local w, h = love.graphics.getDimensions()
    local m = UI.Theme.metrics
    local pad = m.padding

    local listW = math.min(UI.Theme.px(LIST_MAX_W), w * 0.6)
    local rowH = UI.Theme.px(ROW_H)
    local listH = #ROWS * rowH

    local panelW = listW + pad * 2
    local panelH = listH + pad * 2
    local backW = math.min(UI.Theme.px(BACK_W), panelW)

    local top = h * HEADING_Y_RATIO + UI.Theme.font("heading"):getHeight() + m.rowGap
    local blockH = panelH + m.rowGap + m.rowHeight
    local panelY = math.max(top, math.min(h * LIST_Y_RATIO, UI.Label.hintY() - m.rowGap - blockH))
    local panelX = (w - panelW) / 2

    self.panel = { x = panelX, y = panelY, w = panelW, h = panelH }

    self.rows = self.rows or {}
    self.rowAlpha = self.rowAlpha or {}
    for i = 1, #ROWS do
        self.rows[i] = { x = panelX + pad, y = panelY + pad + (i - 1) * rowH, w = listW, h = rowH }
        self.rowAlpha[i] = self.rowAlpha[i] or 1
    end

    self.backButton:setBounds((w - backW) / 2, panelY + panelH + m.rowGap, backW, m.rowHeight)

    self.noteW = math.min(w * 0.7, UI.Theme.px(STATUS_MAX_W))
    self.statusY = self.backButton.y + self.backButton.h + m.rowGap * 2
    local text, button = self:status()
    self.statusText = text
    if button then
        local smallFont = UI.Theme.font("small")
        local _, lines = smallFont:getWrap(text or "", self.noteW)
        local statusH = math.max(1, #lines) * smallFont:getHeight()
        button:setBounds((w - backW) / 2, self.statusY + statusH + m.rowGap, backW, m.rowHeight)
    end

    self:syncChroma()
end

--- re-lays out for the new window size
function Stats:resize()
    self:layout()
end

--- the status line's button only belongs in the focus order while it's
-- shown; rebuilt whenever that changes so Tab never lands on a hidden
-- button, and so the freshly-hidden one gives its focus back
function Stats:syncFocusWidgets()
    local _, button = self:status()
    self.statusButton = button
    local widgets = { self.backButton }
    if button then widgets[#widgets + 1] = button end
    self.group:setWidgets(widgets)
end

--- brief staggered fade for the rows and the buttons below them; skipped
-- under reduced motion, same restraint Menu's own intro uses. Replayed on
-- every visit, unlike the main menu's (which only plays once, on the way
-- out of loading) -- this screen is a short, deliberate destination players
-- come back to, not a landing page that would wear the cascade out fast
function Stats:playIntro()
    if UI.Motion.reduced then return end
    self.introTime = 0
    self.backButton.introAlpha = 0
    self.enableSharingButton.introAlpha = 0
    self.copyButton.introAlpha = 0
    for i = 1, #ROWS do self.rowAlpha[i] = 0 end
end

---@param dt number
function Stats:update(dt)
    -- an error can arrive (or clear) while the screen is up
    local text, button = self:status()
    if button ~= self.statusButton or (button and text ~= self.statusText) then
        self:syncFocusWidgets()
        self:layout()
    end

    self.group:update(dt)

    self:syncChroma()
    if self.chroma then
        self.chroma.speed = UI.Motion.reduced and 0 or CHROMA_SPEED
        self.chroma:update(dt)
    end

    if self.introTime then
        self.introTime = self.introTime + dt
        local finished = true
        for i = 1, #ROWS do
            local t = (self.introTime - (i - 1) * INTRO_STAGGER) / INTRO_DURATION
            if t < 1 then finished = false end
            self.rowAlpha[i] = Ease.outCubic(Math.clamp01(t))
        end
        local buttonT = (self.introTime - #ROWS * INTRO_STAGGER) / INTRO_DURATION
        if buttonT < 1 then finished = false end
        local buttonAlpha = Ease.outCubic(Math.clamp01(buttonT))
        self.backButton.introAlpha = buttonAlpha
        self.enableSharingButton.introAlpha = buttonAlpha
        self.copyButton.introAlpha = buttonAlpha
        if finished then self.introTime = nil end
    end
end

---@param key string
function Stats:keypressed(key)
    if key == "escape" then
        self:leave()
        return
    end
    self.group:keypressed(key)
end

--- pass-throughs to the focus group
function Stats:mousepressed(x, y, button)  self.group:mousepressed(x, y, button)  end
function Stats:mousereleased(x, y, button) self.group:mousereleased(x, y, button) end

---@param x number
---@param y number
function Stats:mousemoved(x, y)
    self.mouseX, self.mouseY = x, y
    self.group:mousemoved(x, y)
end

--- the line under the readout: an error with its code (over any stale
-- values still showing), how fresh the values are, or why there are none
---@return string|nil text
---@return table|nil button # the button that goes with this line, if any
---@return boolean|nil isError
function Stats:status()
    local err = StatsService.enabled and StatsService.lastError()
    if err then
        local key = err.code == "ST-NOHTTPS" and "stats.error.unsupported" or "stats.error.generic"
        return I18n.t(key) .. "\n" .. I18n.t("stats.error.code", { code = err.code }), self.copyButton, true
    end
    for _, row in ipairs(ROWS) do
        if row.get() ~= nil then return self:updatedText() end
    end
    if not StatsService.enabled then return I18n.t("stats.sharingOff"), self.enableSharingButton end
    -- fresh off Stats.start(), an empty readout just means the first reply
    -- hasn't landed yet -- not worth alarming the player before it's had a
    -- fair chance to arrive
    local elapsed = StatsService.startedAt and (love.timer.getTime() - StatsService.startedAt) or 0
    return I18n.t(elapsed < STATUS_GRACE_SECONDS and "stats.loading" or "stats.waiting")
end

---@return string|nil # "Updated Xs ago", once any value has arrived
function Stats:updatedText()
    if not StatsService.lastUpdated then return nil end
    local elapsed = love.timer.getTime() - StatsService.lastUpdated
    return I18n.t("stats.updated", { t = Format.duration(elapsed) })
end

---@param tone? "gold"|string # "rainbow" never reaches here -- that row always
-- takes the drawChromaValue branch below, since self.chroma is guaranteed
-- built by the time draw() runs (layout() -> syncChroma(), every enter())
---@return number[]
function Stats:valueColor(tone)
    if tone == "gold" then return UI.Theme.fixedColors.gold end
    return UI.Theme.colors.accent
end

--- the rainbow row's value, through the same chroma shader as the menu title
---@param y number
function Stats:drawChromaValue(y)
    local row = self.rows[CHROMA_ROW]
    local offset = UI.Label.shadowOffset()

    self.chroma:setPosition(row.x, y)
    UI.Theme.setColor(UI.Theme.colors.shadow)
    love.graphics.draw(self.chroma.textObject, row.x + offset, y + offset)
    love.graphics.setColor(1, 1, 1, 1)

    self.chroma:drawChroma()
end

-- a quiet static backlight for the two "record" rows, tying them into the
-- same glow language every other focusable row draws with, without
-- implying they're interactive (no pulse, no focus-driven intensity)
local ROW_GLOW_INTENSITY = 0.3

---@param i integer
---@return number[]|nil # nil for a row that gets no glow
local function rowGlowColor(i)
    local tone = ROWS[i].tone
    if tone == "gold" then return UI.Theme.fixedColors.gold end
    if tone == "rainbow" then return UI.Theme.colors.accent end
    return nil
end

--- heading, the four rows in their own card, the back button (plus an
-- enable-sharing shortcut while sharing is off), and a status/staleness
-- line beneath it
function Stats:draw()
    local h = love.graphics.getHeight()

    UI.Label.draw{
        text = I18n.t("stats.title"),
        y = h * HEADING_Y_RATIO,
        font = UI.Theme.font("heading"),
        shadow = true,
    }

    UI.Theme.panel(self.panel.x, self.panel.y, self.panel.w, self.panel.h)

    local labelFont = UI.Theme.font("small")
    local valueFont = UI.Theme.font("body")
    local hairline = math.max(1, UI.Theme.px(1))

    for i, row in ipairs(self.rows) do
        local alpha = self.rowAlpha[i]

        if i > 1 then
            UI.Theme.setColor(UI.Theme.colors.panelBorder, 0.5 * alpha)
            love.graphics.rectangle("fill", row.x, row.y, row.w, hairline)
        end

        local glowColor = rowGlowColor(i)
        if glowColor then
            UI.Theme.glowRect(row.x, row.y, row.w, row.h, UI.Theme.metrics.radius,
                ROW_GLOW_INTENSITY * alpha, glowColor, true)
        end

        UI.Label.draw{
            text = I18n.t(ROWS[i].labelKey),
            x = row.x, y = UI.Theme.centerY(row.y, row.h, labelFont),
            width = row.w, align = "left",
            font = labelFont,
            color = UI.Theme.colors.textMuted,
            alpha = alpha,
            shadow = true,
        }

        local value = ROWS[i].get()
        local valueY = UI.Theme.centerY(row.y, row.h, valueFont)

        if ROWS[i].tone == "rainbow" and value and self.chroma then
            self:drawChromaValue(valueY) -- not alpha-faded: drawChroma always draws opaque (see textFactory.lua)
        else
            UI.Label.draw{
                text = valueText(value),
                x = row.x, y = valueY,
                width = row.w, align = "right",
                font = valueFont,
                color = value and self:valueColor(ROWS[i].tone) or UI.Theme.colors.textDim,
                alpha = alpha,
                shadow = true,
            }
        end
    end

    self.backButton:draw()

    local text, button, isError = self:status()
    if text then
        UI.Label.draw{
            text = text,
            x = (love.graphics.getWidth() - self.noteW) / 2,
            y = self.statusY,
            width = self.noteW,
            font = UI.Theme.font("small"),
            color = isError and UI.Theme.colors.warning or UI.Theme.colors.textDim,
            shadow = true,
        }
    end
    if button then button:draw() end

    UI.Label.hint(I18n.t("stats.hint"))

    local overWidget, dangerous = self.group:hovering(self.mouseX or -1, self.mouseY or -1)
    UI.Cursor.setHover(self.mouseX ~= nil and overWidget, dangerous)
end

return Stats
