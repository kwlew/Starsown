--- Achievements: an intentional empty state until there are any.

local BackButton = require("states.shared.backButton")
local I18n = require("core.i18n")
local Pointer = require("states.shared.pointer")
local Presence = require("services.presence")
local StateManager = require("core.state.manager")
local UI = require("ui")

local Achievements = {}

local HEADING_Y_RATIO = 0.12
local BLOCK_Y_RATIO = 0.42
local MESSAGE_MAX_W = 520
local MESSAGE_RATIO = 0.8
local BUTTON_W = 180

---@param previousName string|nil
---@param opts? table # { returnTo?: string }
function Achievements:enter(previousName, opts)
    if not self.group then
        self.pointer = Pointer.new()
        self.backButton = BackButton("achievements.back", function() self:leave() end)
        self.group = UI.FocusGroup.new()
        self.group.onFocusChanged = UI.Sfx.focus
        self.group:setWidgets{ self.backButton }
    end
    Presence.show("achievements")
    self.returnTo = StateManager.returnTarget(previousName, opts, "achievements")
    self.pointer:reset()
    self:layout()
end

function Achievements:leave()
    UI.Sfx.select()
    StateManager.fadeTo(self.returnTo)
end

function Achievements:layout()
    local w, h = love.graphics.getDimensions()
    local m, font = UI.Theme.metrics, UI.Theme.font("body")
    local messageW = math.min(UI.Theme.px(MESSAGE_MAX_W), w * MESSAGE_RATIO)
    local _, lines = font:getWrap(I18n.t("achievements.empty"), messageW)
    local messageH = #lines * font:getHeight()

    local top = h * HEADING_Y_RATIO + UI.Theme.font("heading"):getHeight() + m.rowGap
    local bottom = UI.Hint.y() - m.rowGap - (messageH + m.rowGap + m.rowHeight)
    local y = math.max(top, math.min(h * BLOCK_Y_RATIO, bottom))
    local buttonW = math.min(UI.Theme.px(BUTTON_W), messageW)

    self.message = { x = (w - messageW) / 2, y = y, w = messageW }
    self.backButton:setBounds((w - buttonW) / 2, y + messageH + m.rowGap, buttonW, m.rowHeight)
end

function Achievements:resize()
    self:layout()
end

---@param dt number
function Achievements:update(dt)
    self.group:update(dt)
    self.pointer:hover(self.group)
end

function Achievements:keypressed(key)
    if key == "escape" then return self:leave() end
    self.group:keypressed(key)
end

function Achievements:mousemoved(x, y)
    self.pointer:move(x, y)
    self.group:mousemoved(x, y)
end

function Achievements:mousepressed(x, y, button) self.group:mousepressed(x, y, button) end
function Achievements:mousereleased(x, y, button) self.group:mousereleased(x, y, button) end

function Achievements:draw()
    UI.Label.draw{ text = I18n.t("achievements.title"), y = love.graphics.getHeight() * HEADING_Y_RATIO,
        font = UI.Theme.font("heading"), shadow = true }
    UI.Label.draw{ text = I18n.t("achievements.empty"), x = self.message.x, y = self.message.y,
        width = self.message.w, font = UI.Theme.font("body"), color = UI.Theme.colors.textMuted, shadow = true }
    self.backButton:draw()
    UI.Hint.draw(I18n.t("achievements.hint"))
end

return Achievements
