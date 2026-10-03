--- World stats screen: the readout, a status line, and Back.

local Assets = require("core.assets")
local BackButton = require("states.shared.backButton")
local I18n = require("core.i18n")
local Pointer = require("states.shared.pointer")
local Presence = require("services.presence")
local Readout = require("states.stats.readout")
local Settings = require("core.settings")
local StateManager = require("core.state.manager")
local Status = require("states.stats.status")
local StatsService = require("services.stats")
local UI = require("ui")

local Stats = {}

local HEADING_Y_RATIO = 0.12
local LIST_Y_RATIO = 0.30
local BUTTON_W = 240
local NOTE_MAX_W = 460
local NOTE_RATIO = 0.7
local COPIED_SECONDS = 2

function Stats:build()
    self.pointer = Pointer.new()
    self.readout = Readout.new()
    self.group = UI.FocusGroup.new()
    self.group.onFocusChanged = UI.Sfx.focus
    self.intro = UI.Intro.new{ duration = 1.0, stagger = 0.05 }

    self.backButton = BackButton("stats.back", function() self:leave() end)
    self.actions = {
        enable = UI.Button.new{
            label = function() return I18n.t("stats.enableSharing") end,
            onSelect = function()
                UI.Sfx.select()
                StatsService.setConsent(self.settings, true)
                self:refresh()
            end,
        },
        copy = UI.Button.new{
            label = function()
                local copied = self.copiedAt and love.timer.getTime() - self.copiedAt < COPIED_SECONDS
                return I18n.t(copied and "stats.copied" or "stats.copyDetails")
            end,
            onSelect = function()
                UI.Sfx.select()
                love.system.setClipboardText(StatsService.reportText())
                self.copiedAt = love.timer.getTime()
            end,
        },
    }
end

---@param previousName string|nil
---@param opts? table # { returnTo?: string }
function Stats:enter(previousName, opts)
    if not self.readout then self:build() end
    Presence.show("stats")
    self.returnTo = StateManager.returnTarget(previousName, opts, "stats")
    self.settings = Assets.get("settings") or Settings.load()
    self.pointer:reset()
    self:refresh()

    local animated = {}
    for _, row in ipairs(self.readout.rows) do animated[#animated + 1] = row end
    animated[#animated + 1] = self.backButton
    for _, button in pairs(self.actions) do animated[#animated + 1] = button end
    self.intro:play(animated)
end

function Stats:leave()
    UI.Sfx.select()
    StateManager.fadeTo(self.returnTo)
end

--- re-reads the status; a shown action button joins focus
function Stats:refresh()
    local text, action, isError = Status.current(self.readout:hasValues())
    self.statusText, self.statusError = text, isError
    self.actionButton = action and self.actions[action] or nil
    self.group:setWidgets(self.actionButton and { self.backButton, self.actionButton } or { self.backButton })
    self:layout()
end

--- keeps the card clear of the heading and the hint
function Stats:layout()
    local w, h = love.graphics.getDimensions()
    local m = UI.Theme.metrics
    local panelW, panelH = self.readout:size()
    local buttonW = math.min(UI.Theme.px(BUTTON_W), panelW)
    local buttonX = (w - buttonW) / 2

    local top = h * HEADING_Y_RATIO + UI.Theme.font("heading"):getHeight() + m.rowGap
    local bottom = UI.Hint.y() - m.rowGap - (panelH + m.rowGap + m.rowHeight)
    local panelY = math.max(top, math.min(h * LIST_Y_RATIO, bottom))
    self.readout:layout((w - panelW) / 2, panelY)
    self.backButton:setBounds(buttonX, panelY + panelH + m.rowGap, buttonW, m.rowHeight)

    self.noteW = math.min(w * NOTE_RATIO, UI.Theme.px(NOTE_MAX_W))
    self.noteY = self.backButton.y + self.backButton.h + m.rowGap * 2
    if self.actionButton then
        local font = UI.Theme.font("small")
        local _, lines = font:getWrap(self.statusText or "", self.noteW)
        local noteH = math.max(1, #lines) * font:getHeight()
        self.actionButton:setBounds(buttonX, self.noteY + noteH + m.rowGap, buttonW, m.rowHeight)
    end
end

function Stats:resize()
    self:layout()
end

---@param dt number
function Stats:update(dt)
    local text, action, isError = Status.current(self.readout:hasValues())
    local button = action and self.actions[action] or nil
    if button ~= self.actionButton or (button and text ~= self.statusText) then
        self:refresh() -- the layout depends on it
    else
        self.statusText, self.statusError = text, isError
    end
    self.group:update(dt)
    self.readout:update(dt)
    self.intro:update(dt)
    self.pointer:hover(self.group)
end

function Stats:keypressed(key)
    if key == "escape" then return self:leave() end
    self.group:keypressed(key)
end

function Stats:mousemoved(x, y)
    self.pointer:move(x, y)
    self.group:mousemoved(x, y)
end

function Stats:mousepressed(x, y, button) self.group:mousepressed(x, y, button) end
function Stats:mousereleased(x, y, button) self.group:mousereleased(x, y, button) end

function Stats:draw()
    local c = UI.Theme.colors
    UI.Label.draw{ text = I18n.t("stats.title"), y = love.graphics.getHeight() * HEADING_Y_RATIO,
        font = UI.Theme.font("heading"), shadow = true }

    self.readout:draw()
    self.backButton:draw()

    if self.statusText then
        UI.Label.draw{ text = self.statusText, x = (love.graphics.getWidth() - self.noteW) / 2, y = self.noteY,
            width = self.noteW, font = UI.Theme.font("small"), shadow = true,
            color = self.statusError and c.warning or c.textDim }
    end
    if self.actionButton then self.actionButton:draw() end

    UI.Hint.draw(I18n.t("stats.hint"))
end

return Stats
