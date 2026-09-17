--- Placeholder screen: no achievements are defined yet, so this shows an
-- intentional empty state (heading, explanatory line, Back) rather than the
-- blank screen a stub with no draw() left behind. Real cards/filters/unlock
-- notifications wait on achievement definitions and persistence (Step 9).

local StateManager = require "core.stateManager"
local Presence = require "services.presence"
local Globals = require "globals"
local UI = require "ui"
local I18n = require "core.i18n"

local HEADING_Y_RATIO = 0.12
local MESSAGE_MAX_W = 520

local Achievements = {}

---@param previousName string|nil
---@param opts? table # { returnTo?: string }
function Achievements:enter(previousName, opts)
    Presence.set{
        details = "Achievements",
        state = "Viewing achievements",
        smallText = "Achievements",
        startedAt = Globals.game.startedAt,
    }
    self.returnTo = StateManager.returnTarget(previousName, opts, "achievements")

    self.mouseX, self.mouseY = love.mouse.getPosition()

    if not self.group then
        self.group = UI.FocusGroup.new()
        self.group.onFocusChanged = UI.Sfx.focus
    end

    if not self.backButton then
        self.backButton = UI.Button.new{
            label = function() return I18n.t("achievements.back") end,
            onSelect = function() self:leave() end,
        }
        self.group:setWidgets{ self.backButton }
    end

    self:layout()
end

--- fades back to whichever screen opened this one
function Achievements:leave()
    UI.Sfx.select()
    StateManager.fadeTo(self.returnTo)
end

--- centers the message block, keeping it clear of the heading above and the hint below
function Achievements:layout()
    local w, h = love.graphics.getDimensions()
    local m = UI.Theme.metrics
    local font = UI.Theme.font("body")

    local messageW = math.min(UI.Theme.px(MESSAGE_MAX_W), w * 0.8)
    local _, lines = font:getWrap(I18n.t("achievements.empty"), messageW)
    local messageH = #lines * font:getHeight()

    local backW = math.min(UI.Theme.px(180), messageW)
    local blockH = messageH + m.rowGap + m.rowHeight
    local top = h * HEADING_Y_RATIO + UI.Theme.font("heading"):getHeight() + m.rowGap
    local blockY = math.max(top, math.min(h * 0.42, UI.Label.hintY() - m.rowGap - blockH))

    self.messageRect = { x = (w - messageW) / 2, y = blockY, w = messageW, h = messageH }
    self.backButton:setBounds((w - backW) / 2, blockY + messageH + m.rowGap, backW, m.rowHeight)
end

function Achievements:resize()
    self:layout()
end

function Achievements:update(dt)
    self.group:update(dt)
end

---@param key string
function Achievements:keypressed(key)
    if key == "escape" then
        self:leave()
        return
    end
    self.group:keypressed(key)
end

function Achievements:mousepressed(x, y, button)  self.group:mousepressed(x, y, button)  end
function Achievements:mousereleased(x, y, button) self.group:mousereleased(x, y, button) end

---@param x number
---@param y number
function Achievements:mousemoved(x, y)
    self.mouseX, self.mouseY = x, y
    self.group:mousemoved(x, y)
end

function Achievements:draw()
    local h = love.graphics.getHeight()

    UI.Label.draw{
        text = I18n.t("achievements.title"),
        y = h * HEADING_Y_RATIO,
        font = UI.Theme.font("heading"),
        shadow = true,
    }

    local rect = self.messageRect
    UI.Label.draw{
        text = I18n.t("achievements.empty"),
        x = rect.x, y = rect.y, width = rect.w,
        align = "center",
        font = UI.Theme.font("body"),
        color = UI.Theme.colors.textMuted,
        shadow = true,
    }

    self.backButton:draw()
    UI.Label.hint(I18n.t("achievements.hint"))

    local overWidget, dangerous = self.group:hovering(self.mouseX or -1, self.mouseY or -1)
    UI.Cursor.setHover(self.mouseX ~= nil and overWidget, dangerous)
end

return Achievements
