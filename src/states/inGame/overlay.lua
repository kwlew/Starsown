--- A fading panel over the run: title, divider, menu, hint.

local Ease = require("utils.ease")
local I18n = require("core.i18n")
local UI = require("ui")

local Overlay = {}
Overlay.__index = Overlay

local PANEL_PAD = 28
local HEADING_GAP = 14
local DIVIDER_W = 64
local DIVIDER_H = 2
local MENU_GAP = 20
local SLIDE = 16       -- design px it rises while fading in
local FADE_SPEED = 18
local HINT_CLEARANCE = 56 -- kept free under a low panel

---@param config table # { items, title, hint, divider?, anchor?, scrim?, panelAlpha? }
---@return table
function Overlay.new(config)
    local self = setmetatable({
        menu = UI.Menu.new(config.items),
        title = config.title,          -- i18n key
        hint = config.hint,            -- i18n key
        divider = config.divider or "accent", -- theme role
        anchor = config.anchor or 0.5, -- panel centre, fraction of height
        scrim = config.scrim or 1,
        panelAlpha = config.panelAlpha or 1,
        open = false,
        shown = 0,
    }, Overlay)
    self.menu:onFocusChanged(UI.Sfx.focus)
    return self
end

---@param open boolean
---@param instant? boolean # skip the fade
function Overlay:setOpen(open, instant)
    self.open = open
    if instant then self.shown = open and 1 or 0 end
    if open then
        self.menu:setFocus(1, true)
        self:layout()
    end
end

---@return boolean
function Overlay:isVisible()
    return self.shown > 0.001
end

function Overlay:layout()
    local px, m = UI.Theme.px, UI.Theme.metrics
    local w, h = love.graphics.getDimensions()
    local buttons = self.menu:buttons()
    local heading = UI.Theme.font("heading")
    local pad = px(PANEL_PAD)

    local menuH = #buttons * m.rowHeight + (#buttons - 1) * m.rowGap
    local panelH = pad * 2 + heading:getHeight() + px(HEADING_GAP) * 2 + px(MENU_GAP) + menuH
    local centred = math.floor((h - panelH) / 2)
    local anchored = math.floor(h * self.anchor - panelH / 2)
    local top = math.max(centred, math.min(anchored, h - panelH - px(HINT_CLEARANCE)))

    self.menu:layout(top + pad + heading:getHeight() + px(HEADING_GAP) * 2 + px(MENU_GAP))
    local panelW = math.max(buttons[1].w, heading:getWidth(I18n.t(self.title))) + pad * 2
    self.panel = { x = math.floor((w - panelW) / 2), y = top, w = panelW, h = panelH }
    self.headingY = top + pad
    self.dividerY = self.headingY + heading:getHeight() + px(HEADING_GAP)
end

---@param dt number
function Overlay:update(dt)
    self.shown = UI.Theme.approach(self.shown, self.open and 1 or 0, dt, FADE_SPEED)
    if self.open then self.menu:update(dt) end
end

---@param alpha number
function Overlay:drawPanel(alpha)
    local c, p, radius = UI.Theme.colors, self.panel, UI.Theme.metrics.radius
    UI.Theme.setColor(c.panel, (c.panel[4] or 1) * alpha * self.panelAlpha)
    love.graphics.rectangle("fill", p.x, p.y, p.w, p.h, radius, radius, 8)
    UI.Theme.setColor(c.panelBorder, (c.panelBorder[4] or 1) * alpha)
    love.graphics.rectangle("line", p.x, p.y, p.w, p.h, radius, radius, 8)

    UI.Label.draw{ text = I18n.t(self.title), y = self.headingY,
        font = UI.Theme.font("heading"), alpha = alpha, shadow = true }

    local dividerW = UI.Theme.px(DIVIDER_W)
    UI.Theme.setColor(c[self.divider], alpha)
    love.graphics.rectangle("fill", (love.graphics.getWidth() - dividerW) / 2, self.dividerY,
        dividerW, math.max(1, UI.Theme.px(DIVIDER_H)))
end

function Overlay:draw()
    if not self:isVisible() then return end
    local c = UI.Theme.colors
    local alpha = Ease.outCubic(self.shown)

    UI.Theme.setColor(c.scrim, (c.scrim[4] or 1) * alpha * self.scrim)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())

    love.graphics.push()
    love.graphics.translate(0, UI.Motion.reduced and 0 or UI.Theme.px(SLIDE) * (1 - alpha))
    self:drawPanel(alpha)
    for _, button in ipairs(self.menu:buttons()) do button.introAlpha = alpha end
    self.menu:draw()
    love.graphics.pop()

    if self.open and self.shown > 0.5 then UI.Hint.draw(I18n.t(self.hint), true) end
end

return Overlay
