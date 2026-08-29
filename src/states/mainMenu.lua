-- Title screen: chroma title (via TextFactory) plus a keyboard/mouse menu of
-- themed buttons. Also the splash tag hanging under the title
-- (see ui/text/splash.lua).

local StateManager  = require "core.stateManager"
local Assets        = require "core.assets"
local Presence      = require "services.presence"
local Menu          = require "ui.widgets.menu"
local TextFactory   = require "ui.text.textFactory"
local UI            = require "ui"
local I18n          = require "core.i18n"
local Particles     = require "particles"
local GameTitle     = require "ui.text.gameTitle"
local Splash        = require "ui.text.splash"
local Globals       = require "globals"
local Format        = require "utils.format"

local Stats         = require "services.stats"

-- fractions of window size, so layout survives resizing at any resolution;
-- the title's ratio lives in gameTitle.lua since loading animates to it
local MENU_Y_RATIO = 0.44

local GITHUB_URL = "https://github.com/kwlew/TD-Idle"
local DISCORD_URL = "https://discord.gg/HEQ9PB5UHq"
local SOCIAL_ICON_SIZE = 26
local CORNER_PAD = 12
local CORNER_GAP = 10 -- between the online-count label and the version label it sits beside

local MainMenu = {}

local buildTitle = GameTitle.build

local function buildVersionLabel()
    return TextFactory:new{
        text = "v" .. Globals.game.version,
        font = UI.Theme.font("small"),
        color = UI.Theme.colors.textDim,
    }
end

local function buildOnlinePlayersLabel(count)
    if not count then return nil end
    return TextFactory:new{
        text = I18n.t("menu.onlinePlayers", { n = Format.group(count) }),
        font = UI.Theme.font("small"),
        color = UI.Theme.colors.textDim,
    }
end

local function inheritSky(existing, name, build)
    local layer = existing or Assets.get(name) or build()
    layer.alpha = 1 -- loading may have handed it over mid-fade
    return layer
end

function MainMenu:enter(previousName)
    UI.Music.start()
    self.title = buildTitle()
    self.version = buildVersionLabel()
    self.onlineCount = Stats.online
    self.onlinePlayers = buildOnlinePlayersLabel(self.onlineCount)
    -- bottom-left row, github first; order here is left-to-right order (see layout)
    self.links = self.links or {
        UI.IconLink.new{ mark = "github", url = GITHUB_URL },
        UI.IconLink.new{ mark = "discord", url = DISCORD_URL },
    }
    self.mouseX, self.mouseY = love.mouse.getPosition()
    self.starfield = self.starfield or Globals.menu.Particles.starfield
    self.stars = inheritSky(self.stars, "stars", function()
        local stars = Particles.Stars.new{}
        stars:spawnStars()
        return stars
    end)
    self.nebula = inheritSky(self.nebula, "nebula", function()
        return Particles.Nebula.new{}:bake()
    end)

    -- picked once per session, like the menu below, so it doesn't reroll
    -- every time the player bounces back from Options
    self.splash = self.splash or Splash.pick()

    if not self.menu then -- stateless between visits, so build it just once
        self.menu = Menu.new({
            { label = function() return I18n.t("menu.play") end, onSelect = function()
                UI.Sfx.select()
                --StateManager.fadeTo("play")
            end },
            { label = function() return I18n.t("menu.stats") end, onSelect = function()
                UI.Sfx.select()
                StateManager.fadeTo("stats", { returnTo = "mainMenu" })
            end },
            { label = function() return I18n.t("menu.achievements") end, onSelect = function()
                UI.Sfx.select()
                StateManager.fadeTo("achievements", { returnTo = "mainMenu" })
            end },
            { label = function() return I18n.t("menu.options") end, onSelect = function()
                UI.Sfx.select()
                StateManager.fadeTo("options", { returnTo = "mainMenu" })
            end },
            { label = function() return I18n.t("menu.quit") end, danger = true,
              onSelect = function()
                love.event.quit()
            end },
        })
        self.menu:onFocusChanged(UI.Sfx.focus)
    end

    -- Fade from loading.
    if previousName == "loading" then
        self.menu:playIntro()
    end

    Presence.set{ details = "Main Menu", state = "Getting ready",
                  smallText = "In the menu" }

    self:layout()
end

function MainMenu:layout()
    local w, h = love.graphics.getDimensions()
    local pad = UI.Theme.px(CORNER_PAD)
    local iconSize = UI.Theme.px(SOCIAL_ICON_SIZE)

    self.title.y = h * GameTitle.MENU_Y_RATIO

    local iconY = h - iconSize - pad
    local iconX = pad
    for _, link in ipairs(self.links) do
        link:setBounds(iconX, iconY, iconSize, iconSize)
        iconX = iconX + iconSize + pad
    end

    local versionY = h - pad - self.version.font:getHeight()
    local versionX = w - self.version.font:getWidth(self.version.text) - pad
    self.version:setPosition(versionX, versionY)

    if self.onlinePlayers then
        local gap = UI.Theme.px(CORNER_GAP)
        local onlineX = versionX - gap - self.onlinePlayers.font:getWidth(self.onlinePlayers.text)
        self.onlinePlayers:setPosition(onlineX, versionY)
    end

    self.menu:layout(h * MENU_Y_RATIO)
end

function MainMenu:update(dt)
    self.nebula:update(dt)
    self.stars:update(dt)
    self.starfield:update(dt)
    self.title:update(dt)
    self.splash:update(dt)
    self.menu:update(dt)

    if Stats.online ~= self.onlineCount then
        self.onlineCount = Stats.online
        self.onlinePlayers = buildOnlinePlayersLabel(self.onlineCount)
        self:layout()
    end
end

function MainMenu:resize(w, h, rescaled)
    self.title = buildTitle()
    if rescaled then
        self.version = buildVersionLabel()
        self.onlinePlayers = buildOnlinePlayersLabel(self.onlineCount)
    end
    self:layout()
end

function MainMenu:keypressed(key)
    self.menu:keypressed(key)
end

-- true if the pointer is over any corner icon link -- used to color the cursor
function MainMenu:anyLinkHover()
    for _, link in ipairs(self.links) do
        if link.hover then return true end
    end
    return false
end

function MainMenu:mousemoved(x, y)
    self.menu:mousemoved(x, y)
    for _, link in ipairs(self.links) do link:mousemoved(x, y) end
    self.mouseX, self.mouseY = x, y
end

function MainMenu:mousepressed(x, y, button)
    if self.menu:mousepressed(x, y, button) then return end -- UI wins the click; only empty sky reaches the starfield
    for _, link in ipairs(self.links) do
        if link:mousepressed(x, y, button) then return end
    end

    local hit, golden, rainbow = self.starfield:mousepressed(x, y, button)
    if not hit then return end -- a click on empty sky is not a pop
    Stats.pop(rainbow and "rainbow" or golden and "golden" or "normal")
end

function MainMenu:mousereleased(x, y, button)
    self.menu:mousereleased(x, y, button)
    for _, link in ipairs(self.links) do link:mousereleased(x, y, button) end
end

function MainMenu:draw()
    self.nebula:draw()

    self.stars:draw()

    self.starfield:draw()

    self.version:draw()

    if self.onlinePlayers then
        self.onlinePlayers:draw()
    end

    for _, link in ipairs(self.links) do link:draw() end

    self.title:drawChroma()
    self.splash:draw(self.title, love.graphics.getWidth())

    self.menu:draw()

    UI.Label.hint(I18n.t("menu.hint"), true)

    -- link hover never carries danger (they're plain links), so the menu's own flag decides the color
    local overMenu, dangerous = self.menu:hovering(self.mouseX or -1, self.mouseY or -1)
    UI.Cursor.setHover(self.mouseX ~= nil and (self:anyLinkHover() or overMenu), dangerous)
end

return MainMenu
