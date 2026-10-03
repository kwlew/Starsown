--- Title screen: title, splash, menu and the live sky.

local Assets = require("core.assets")
local Backdrop = require("states.shared.backdrop")
local ConsentQueue = require("states.mainMenu.consent")
local Corner = require("states.mainMenu.corner")
local I18n = require("core.i18n")
local Music = require("core.audio.music")
local Pointer = require("states.shared.pointer")
local Presence = require("services.presence")
local Settings = require("core.settings")
local ShootingStars = require("states.mainMenu.shootingStars")
local StateManager = require("core.state.manager")
local Stats = require("services.stats")
local UI = require("ui")

local MainMenu = {}

local MENU_Y_RATIO = 0.44

---@param name string
---@param opts? table
local function go(name, opts)
    UI.Sfx.select()
    StateManager.fadeTo(name, opts)
end

---@return table # a UI.Menu
local function buildMenu()
    return UI.Menu.new{
        { label = function() return I18n.t("menu.play") end, icon = "play", primary = true,
          onSelect = function() go("game") end },
        { label = function() return I18n.t("menu.stats") end, icon = "bars",
          onSelect = function() go("stats", { returnTo = "mainMenu" }) end },
        { label = function() return I18n.t("menu.options") end, icon = "gear",
          onSelect = function() go("options", { returnTo = "mainMenu" }) end },
        { label = function() return I18n.t("menu.quit") end, icon = "quit", danger = true,
          onSelect = function() love.event.quit() end },
    }
end

--- built once; the menu holds no state between visits
function MainMenu:build()
    self.settings = Assets.get("settings") or Settings.load()
    self.menu = buildMenu()
    self.corner = Corner.new()
    self.splash = UI.Splash.pick(I18n.list("menu.splashes"))
    self.shootingStars = ShootingStars.new()
    self.consent = ConsentQueue.new(self.settings)
    self.pointer = Pointer.new()

    -- one focus order: menu buttons, then corner links
    self.group = UI.FocusGroup.new()
    self.group.onFocusChanged = UI.Sfx.focus
    local widgets = {}
    for _, button in ipairs(self.menu:buttons()) do widgets[#widgets + 1] = button end
    for _, link in ipairs(self.corner.links) do widgets[#widgets + 1] = link end
    self.group:setWidgets(widgets)
end

---@param previousName string|nil
function MainMenu:enter(previousName)
    if not self.menu then self:build() end
    Music.start("menu")
    Presence.show("mainMenu")

    self.title = UI.GameTitle.build()
    self.stars, self.nebula = Backdrop.get(self.settings)
    self.stars.alpha, self.nebula.alpha = 1, 1 -- loading may hand over mid-fade
    self.corner:setOnline(Stats.online)
    self.pointer:reset()

    if previousName == "loading" then self.menu:playIntro() end
    self:layout()

    self.consent:advance()
end

function MainMenu:layout()
    local h = love.graphics.getHeight()
    self.title.y = h * UI.GameTitle.MENU_Y_RATIO
    self.corner:layout()
    self.menu:layout(h * MENU_Y_RATIO)
    self.consent:layout()
end

function MainMenu:resize()
    self.title = UI.GameTitle.build()
    self:layout()
end

---@return table # whatever has input right now
function MainMenu:input()
    return self.consent:isOpen() and self.consent or self.group
end

---@param dt number
function MainMenu:update(dt)
    local skyPointed = not self.consent:isOpen() and love.window.hasMouseFocus()
    self.stars:setPointer(skyPointed and self.pointer.x or nil, skyPointed and self.pointer.y or nil)
    self.nebula:update(dt)
    self.stars:update(dt)
    self.shootingStars:update(dt)
    self.title:update(dt)
    self.splash:update(dt)
    self.menu:update(dt) -- also drives the intro
    self.corner:update(dt)
    if self.consent:isOpen() then self.consent:update(dt) end

    if Stats.online ~= self.corner.online then self.corner:setOnline(Stats.online) end
    self.pointer:hover(self:input())
end

function MainMenu:keypressed(key)
    self:input():keypressed(key)
end

function MainMenu:mousemoved(x, y)
    self.pointer:move(x, y)
    self:input():mousemoved(x, y)
end

--- UI wins a click; only empty sky reaches stars
function MainMenu:mousepressed(x, y, button)
    if self:input():mousepressed(x, y, button) or self.consent:isOpen() then return end
    if button == 1 then ShootingStars.click(self.shootingStars, x, y) end
end

function MainMenu:mousereleased(x, y, button)
    self:input():mousereleased(x, y, button)
end

function MainMenu:draw()
    self.nebula:draw()
    self.stars:draw()
    self.shootingStars:draw()
    self.corner:draw()

    self.title:drawChroma()
    self.splash:draw(self.title, love.graphics.getWidth())
    self.menu:draw()
    UI.Hint.draw(I18n.t("menu.hint"), true)

    if self.consent:isOpen() then self.consent:draw() end
end

return MainMenu
