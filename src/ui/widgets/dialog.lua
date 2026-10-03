--- Modal confirmation box: a scrim over the screen, a centred panel with a
-- title and wrapped message, and a row of buttons. While open it owns all
-- input -- the screen underneath keeps drawing but stops responding.
--
--   self.dialog = Dialog.new{
--       title   = "Keep these settings?",
--       message = function(d) return ("Reverting in %d..."):format(d:remaining() or 0) end,
--       buttons = {
--           { label = "Revert", onSelect = function() ... end },
--           { label = "Keep", onSelect = function() self.dialog:close() end },
--       },
--       onCancel = function(d) d:close() end, -- Esc, and a click off the panel
--       timeout = 10, onTimeout = function(d) ... end,
--   }
--   self.dialog:openDialog()
--
-- A timeout is what makes a graphics change safe to apply: a resolution the
-- monitor can't show leaves the player unable to click "Revert".
--
-- The owning screen forwards input while it's open and calls layout() on resize:
--   if self.dialog:isOpen() then self.dialog:keypressed(key) return end

local Bindings = require("ui.input.bindings")
local Button = require("ui.widgets.button")
local Countdown = require("utils.countdown")
local FocusGroup = require("ui.widgets.focusGroup")
local Theme = require("ui.core.theme")

local Dialog = {}
Dialog.__index = Dialog

local PANEL_MAX_W = 460  -- design px
local PANEL_MAX_RATIO = 0.8 -- of the window width
local PANEL_PAD = 22
local BUTTON_GAP = 12
local TITLE_GAP = 10     -- title to message
local BUTTON_GAP_Y = 18  -- message to button row

--- built once and reopened, not rebuilt per prompt
---@param config table # { title: string|fun(self: table): string, message: string|fun(self: table): string, buttons?: { label: any, onSelect?: fun(), danger?: boolean }[], onCancel?: fun(self: table), timeout?: number, onTimeout?: fun(self: table), fontRole?: string }
---@return table
function Dialog.new(config)
    local self = setmetatable({
        title = config.title,
        message = config.message,
        fontRole = config.fontRole or "body",
        onCancel = config.onCancel,
        open = false,
        group = FocusGroup.new(),
        buttons = {},
        panel = { x = 0, y = 0, w = 0, h = 0 },
        innerW = 0,
        titleH = 0,
    }, Dialog)

    self.countdown = Countdown.new(config.timeout, config.onTimeout and function()
        config.onTimeout(self)
    end)

    for _, spec in ipairs(config.buttons or {}) do
        self.buttons[#self.buttons + 1] = Button.new{
            label = spec.label,
            onSelect = spec.onSelect,
            danger = spec.danger,
        }
    end
    self.group:setWidgets(self.buttons)
    return self
end

---@return boolean
function Dialog:isOpen()
    return self.open
end

---@return number|nil # seconds until onTimeout, nil without a running countdown
function Dialog:remaining()
    return self.countdown:remaining()
end

---@param fn fun(widget: table, index: integer)
function Dialog:onFocusChanged(fn)
    self.group.onFocusChanged = fn
end

--- shows it, restarts any countdown, and focuses the first button -- so the
-- listed order decides what Enter does
function Dialog:openDialog()
    self.open = true
    self.countdown:start()
    self.group:focusFirst(true)
    self:layout()
end

--- hides it without cancelling; what a button's own handler calls when done
function Dialog:close()
    self.open = false
    self.countdown:stop()
end

--- Esc or a click off the panel: onCancel decides what that means, or it just closes
function Dialog:cancel()
    if self.onCancel then self.onCancel(self) else self:close() end
end

---@return string
function Dialog:titleText()
    return Theme.resolveLabel(self.title, self)
end

---@return string
function Dialog:messageText()
    return Theme.resolveLabel(self.message, self)
end

---@param font any # a love.Font
---@param text string
---@param width number
---@return number # height of the wrapped block
local function wrappedHeight(font, text, width)
    local _, lines = font:getWrap(text, width)
    return math.max(1, #lines) * font:getHeight()
end

--- sizes the panel to its content and lays out the button row. Call on open
-- and on resize.
function Dialog:layout()
    local w, h = love.graphics.getDimensions()
    local pad, rowH = Theme.px(PANEL_PAD), Theme.metrics.rowHeight

    local panelW = math.min(Theme.px(PANEL_MAX_W), w * PANEL_MAX_RATIO)
    self.innerW = panelW - pad * 2
    self.titleH = wrappedHeight(Theme.font("button"), self:titleText(), self.innerW)
    local messageH = wrappedHeight(Theme.font(self.fontRole), self:messageText(), self.innerW)

    local panelH = pad * 2 + self.titleH + Theme.px(TITLE_GAP) + messageH + Theme.px(BUTTON_GAP_Y) + rowH
    self.panel = { x = math.floor((w - panelW) / 2), y = math.floor((h - panelH) / 2), w = panelW, h = panelH }

    local count = #self.buttons
    if count == 0 then return end
    local gap = Theme.px(BUTTON_GAP)
    local buttonW = (self.innerW - gap * (count - 1)) / count
    local buttonY = self.panel.y + panelH - pad - rowH
    for i, button in ipairs(self.buttons) do
        button:setBounds(self.panel.x + pad + (i - 1) * (buttonW + gap), buttonY, buttonW, rowH)
    end
end

--- left/right walk the button row, since it's laid out horizontally
---@param key string
---@return boolean consumed
function Dialog:keypressed(key)
    local action = Bindings.action(key)
    if action == "cancel" then
        self:cancel()
        return true
    elseif action == "left" then
        self.group:moveFocus(-1)
        return true
    elseif action == "right" then
        self.group:moveFocus(1)
        return true
    end
    return self.group:keypressed(key)
end

function Dialog:mousemoved(x, y)
    return self.group:mousemoved(x, y)
end

---@return boolean consumed # always true: nothing behind the scrim ever sees the click
function Dialog:mousepressed(x, y, button)
    if self.group:mousepressed(x, y, button) then return true end
    local p = self.panel
    if button == 1 and not Theme.pointIn(x, y, p.x, p.y, p.w, p.h) then
        self:cancel()
    end
    return true
end

function Dialog:mousereleased(x, y, button)
    return self.group:mousereleased(x, y, button)
end

function Dialog:hovering(x, y)
    return self.group:hovering(x, y)
end

---@param dt number
function Dialog:update(dt)
    self.group:update(dt)
    self.countdown:update(dt)
end

--- scrim, panel, title, wrapped message, buttons
function Dialog:draw()
    local c, p = Theme.colors, self.panel
    local pad = Theme.px(PANEL_PAD)

    Theme.setColor(c.scrim)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())
    Theme.panel(p.x, p.y, p.w, p.h)

    Theme.pushFont(Theme.font("button"))
    Theme.setColor(c.text)
    love.graphics.printf(self:titleText(), p.x + pad, p.y + pad, self.innerW, "center")
    Theme.popFont()

    Theme.pushFont(Theme.font(self.fontRole))
    Theme.setColor(c.textMuted)
    love.graphics.printf(self:messageText(), p.x + pad,
        p.y + pad + self.titleH + Theme.px(TITLE_GAP), self.innerW, "center")
    Theme.popFont()

    self.group:draw()
    love.graphics.setColor(1, 1, 1, 1)
end

return Dialog
