--- Modal confirmation box: a scrim over the screen, a centered panel with a
-- title and wrapped message, and a row of buttons. While open it owns all
-- input -- the screen underneath keeps drawing but stops responding.
--
--   self.dialog = Dialog.new{
--       title   = function() return I18n.t("dialog.revert.title") end,
--       message = function() return I18n.t("dialog.revert.message") end,
--       buttons = {
--           { label = ..., onSelect = function() self.dialog:close() end },
--           { label = ..., onSelect = function() ... end, danger = true },
--       },
--       onCancel = function() self.dialog:close() end,  -- Esc, and the scrim
--   }
--
-- Optionally counts down and acts on its own: timeout = 10, onTimeout = fn --
-- what makes a graphics change safe to apply, since a resolution the monitor
-- can't show leaves the player unable to click "revert". Message functions
-- receive the dialog, so a countdown can read `d.remaining`.
--
-- The owning screen forwards input and calls layout() alongside its own:
--   if self.dialog:isOpen() then self.dialog:keypressed(key) return end

local Theme = require "ui.core.theme"
local Button = require "ui.widgets.button"
local FocusGroup = require "ui.widgets.focusGroup"

local Dialog = {}
Dialog.__index = Dialog

local PANEL_MAX_W = 460 -- design-space px, scaled through Theme.px at use
local PANEL_PAD = 22
local BUTTON_GAP = 12
local TITLE_GAP = 10    -- title baseline to message
local BUTTON_GAP_Y = 18 -- message to button row

--- built once and reopened, not rebuilt per prompt
---@param config table # { title: string|fun(self: table): string, message: string|fun(self: table): string, buttons?: { label: any, onSelect?: fun(), danger?: boolean }[], onCancel?: fun(self: table), timeout?: number, onTimeout?: fun(self: table) }
---@return table
function Dialog.new(config)
    local self = setmetatable({
        title = config.title,
        message = config.message,
        onCancel = config.onCancel,
        timeout = config.timeout,
        onTimeout = config.onTimeout,
        remaining = config.timeout,
        open = false,
        group = FocusGroup.new(),
        panel = { x = 0, y = 0, w = 0, h = 0 },
    }, Dialog)

    local buttons = {}
    for _, spec in ipairs(config.buttons or {}) do
        buttons[#buttons + 1] = Button.new{
            label = spec.label,
            onSelect = spec.onSelect,
            danger = spec.danger, -- destructive choice: draws red at rest, brighter under the cursor
        }
    end
    self.buttons = buttons
    self.group:setWidgets(buttons)

    return self
end

---@return boolean
function Dialog:isOpen()
    return self.open
end

---@param fn fun(widget: table, index: integer)
function Dialog:setFocusSound(fn)
    self.group.onFocusChanged = fn
end

--- shows it, restarts any countdown, and focuses the first button -- so the
-- listed order decides what Enter does (see the stats consent prompt, which
-- lists Decline first for exactly this reason)
function Dialog:openDialog()
    self.open = true
    self.remaining = self.timeout
    self.group:focusFirst()
    self:layout()
end

--- hides it without cancelling; what a button's own handler calls when done
function Dialog:close()
    self.open = false
end

---@return string
function Dialog:titleText()
    return Theme.resolveLabel(self.title, self)
end

---@return string
function Dialog:messageText()
    return Theme.resolveLabel(self.message, self)
end

--- panel is sized to its content: message wraps to the panel's inner width,
-- panel grows to fit. Call on open and on resize.
function Dialog:layout()
    local w, h = love.graphics.getDimensions()
    local pad = Theme.px(PANEL_PAD)
    local m = Theme.metrics

    local panelW = math.min(Theme.px(PANEL_MAX_W), w * 0.8)
    local innerW = panelW - pad * 2

    local titleFont = Theme.font("button")
    local bodyFont = Theme.font("body")
    local _, lines = bodyFont:getWrap(self:messageText(), innerW)
    local messageH = math.max(1, #lines) * bodyFont:getHeight()

    local panelH = pad * 2
        + titleFont:getHeight() + Theme.px(TITLE_GAP)
        + messageH + Theme.px(BUTTON_GAP_Y)
        + m.rowHeight

    self.panel = {
        x = math.floor((w - panelW) / 2),
        y = math.floor((h - panelH) / 2),
        w = panelW,
        h = panelH,
    }
    self.innerW = innerW
    self.messageH = messageH

    local count = #self.buttons
    if count == 0 then return end
    local gap = Theme.px(BUTTON_GAP)
    local buttonW = (innerW - gap * (count - 1)) / count
    local buttonY = self.panel.y + panelH - pad - m.rowHeight
    for i, button in ipairs(self.buttons) do
        button:setBounds(self.panel.x + pad + (i - 1) * (buttonW + gap),
            buttonY, buttonW, m.rowHeight)
    end
end

--- the Esc/scrim path: onCancel decides what that means, or it just closes
function Dialog:cancel()
    if self.onCancel then
        self.onCancel(self)
    else
        self:close()
    end
end

--- left/right walk the button row, since it's laid out horizontally
---@param key string
---@return boolean consumed
function Dialog:keypressed(key)
    if key == "escape" then
        self:cancel()
        return true
    end
    if key == "left" or key == "a" then return self.group:keypressed("up") end
    if key == "right" or key == "d" then return self.group:keypressed("down") end
    return self.group:keypressed(key)
end

---@param x number
---@param y number
---@return boolean consumed
function Dialog:mousemoved(x, y)
    return self.group:mousemoved(x, y)
end

--- a click outside the panel cancels, the way clicking off a modal usually does
---@param x number
---@param y number
---@param button integer
---@return boolean # consumed; always true
function Dialog:mousepressed(x, y, button)
    if self.group:mousepressed(x, y, button) then return true end
    if button == 1 and not Theme.pointIn(x, y, self.panel.x, self.panel.y, self.panel.w, self.panel.h) then
        self:cancel()
    end
    return true -- modal: nothing behind the scrim ever sees the click
end

---@param x number
---@param y number
---@param button integer
---@return boolean consumed
function Dialog:mousereleased(x, y, button)
    return self.group:mousereleased(x, y, button)
end

---@param x number
---@param y number
---@return boolean hovering
---@return boolean? danger
function Dialog:hovering(x, y)
    return self.group:hovering(x, y)
end

--- runs the countdown, if there is one; onTimeout fires once and the timer
-- clears itself
---@param dt number
function Dialog:update(dt)
    self.group:update(dt)

    if self.remaining then
        self.remaining = self.remaining - dt
        if self.remaining <= 0 then
            self.remaining = nil
            if self.onTimeout then self.onTimeout(self) end
        end
    end
end

--- scrim, panel, title, wrapped message, buttons
function Dialog:draw()
    local c = Theme.colors
    local pad = Theme.px(PANEL_PAD)
    local panel = self.panel

    Theme.setColor(c.scrim)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())

    Theme.panel(panel.x, panel.y, panel.w, panel.h)

    local titleFont = Theme.font("button")
    Theme.pushFont(titleFont)
    love.graphics.setColor(c.text)
    love.graphics.printf(self:titleText(), panel.x + pad, panel.y + pad, self.innerW, "center")
    Theme.popFont()

    local bodyFont = Theme.font("body")
    Theme.pushFont(bodyFont)
    love.graphics.setColor(c.textMuted)
    love.graphics.printf(self:messageText(),
        panel.x + pad,
        panel.y + pad + titleFont:getHeight() + Theme.px(TITLE_GAP),
        self.innerW, "center")
    Theme.popFont()

    for _, button in ipairs(self.buttons) do
        button:draw()
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return Dialog
