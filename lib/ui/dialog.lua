-- lib/ui/dialog.lua
-- Modal confirmation box: a scrim over the screen, a centered panel with a
-- title and a wrapped message, and a row of buttons. While open it owns all
-- input — the screen underneath keeps drawing but stops responding.
--
--   self.dialog = Dialog.new{
--       title   = function() return I18n.t("dialog.quit.title") end,
--       message = function() return I18n.t("dialog.quit.message") end,
--       buttons = {
--           { label = ..., onSelect = function() self.dialog:close() end },
--           { label = ..., onSelect = function() ... end, danger = true },
--       },
--       onCancel = function() self.dialog:close() end,  -- Esc, and the scrim
--   }
--
-- Optionally counts down and acts on its own:
--
--       timeout = 10, onTimeout = function() ... end
--
-- which is what makes a graphics change safe to apply — a resolution the
-- monitor can't show leaves the player unable to click "revert", so the dialog
-- reverts itself. Message functions receive the dialog, so a countdown can read
-- `d.remaining`.
--
-- The owning screen forwards input and calls layout() alongside its own:
--
--   if self.dialog:isOpen() then self.dialog:keypressed(key) return end

local Theme = require "lib.ui.theme"
local Button = require "lib.ui.button"
local FocusGroup = require "lib.ui.focusGroup"

local Dialog = {}
Dialog.__index = Dialog

-- Design-space px, scaled through Theme.px at use.
local PANEL_MAX_W = 460
local PANEL_PAD = 22
local BUTTON_GAP = 12
local TITLE_GAP = 10  -- title baseline to message
local BUTTON_GAP_Y = 18 -- message to button row

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
        local button = Button.new{ label = spec.label, onSelect = spec.onSelect }
        -- Marks the destructive choice so draw can tint it; purely visual.
        button.danger = spec.danger or false
        buttons[#buttons + 1] = button
    end
    self.buttons = buttons
    self.group:setWidgets(buttons)

    return self
end

function Dialog:isOpen()
    return self.open
end

function Dialog:setFocusSound(fn)
    self.group.onFocusChanged = fn
end

function Dialog:openDialog()
    self.open = true
    self.remaining = self.timeout
    self.group:focusFirst()
    self:layout()
end

function Dialog:close()
    self.open = false
end

function Dialog:titleText()
    return Theme.resolveLabel(self.title, self)
end

function Dialog:messageText()
    return Theme.resolveLabel(self.message, self)
end

-- Panel is sized to its content: the message wraps to the panel's inner width,
-- and the panel grows to fit however many lines that produced.
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

    -- Buttons share the inner width evenly along the bottom of the panel.
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

function Dialog:cancel()
    if self.onCancel then
        self.onCancel(self)
    else
        self:close()
    end
end

function Dialog:keypressed(key)
    if key == "escape" then
        self:cancel()
        return true
    end
    -- Left/right feel more natural than up/down for a horizontal button row.
    if key == "left" or key == "a" then return self.group:keypressed("up") end
    if key == "right" or key == "d" then return self.group:keypressed("down") end
    return self.group:keypressed(key)
end

function Dialog:mousemoved(x, y)
    return self.group:mousemoved(x, y)
end

-- A click outside the panel cancels, the way clicking off a modal usually does.
function Dialog:mousepressed(x, y, button)
    if self.group:mousepressed(x, y, button) then return true end
    if button == 1 and not Theme.pointIn(x, y, self.panel.x, self.panel.y, self.panel.w, self.panel.h) then
        self:cancel()
    end
    return true -- modal: nothing behind the scrim ever sees the click
end

function Dialog:mousereleased(x, y, button)
    return self.group:mousereleased(x, y, button)
end

function Dialog:hovering(x, y)
    return self.group:hovering(x, y)
end

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

function Dialog:draw()
    local c, m = Theme.colors, Theme.metrics
    local pad = Theme.px(PANEL_PAD)
    local panel = self.panel

    -- Scrim: darkens whatever screen is underneath so the panel reads as the
    -- only thing that can be interacted with.
    love.graphics.setColor(0, 0, 0, 0.6)
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
        -- The destructive choice gets a danger-tinted border on top of the
        -- normal row chrome, so it reads as different before it's read at all.
        if button.danger then
            local d = c.danger
            love.graphics.setColor(d[1], d[2], d[3], 0.55 + 0.45 * button.glow)
            love.graphics.rectangle("line", button.x, button.y, button.w, button.h,
                m.radius, m.radius, 10)
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return Dialog
