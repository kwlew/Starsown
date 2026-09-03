--- Title screen: chroma title (via TextFactory) plus a keyboard/mouse menu of
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
local Settings      = require "core.settings"

local MENU_Y_RATIO = 0.44

local GITHUB_URL = "https://github.com/kwlew/TD-Idle"
local DISCORD_URL = "https://discord.gg/HEQ9PB5UHq"
local SOCIAL_ICON_SIZE = 26
local CORNER_PAD = 12
local CORNER_GAP = 8 -- gap between version and online players labels, bottom-right corner.

local MainMenu = {}

local buildTitle = GameTitle.build

---@return table # a TextFactory
local function buildVersionLabel()
    return TextFactory:new{
        text = "v" .. Globals.game.version,
        font = UI.Theme.font("small"),
        color = UI.Theme.colors.textDim,
    }
end

---@param count integer|nil # nil draws nothing rather than a 0 -- the counter is
-- unknown until the first successful response
---@return table|nil # a TextFactory
local function buildOnlinePlayersLabel(count)
    if not count then return nil end
    return TextFactory:new{
        text = I18n.t("menu.onlinePlayers", { n = Format.group(count) }),
        font = UI.Theme.font("small"),
        color = UI.Theme.colors.textDim,
    }
end

--- reuses the backdrop the loading screen already built, and only generates one
-- if there is nothing to inherit. Alpha is reset because loading may have
-- handed it over mid-fade.
---@param existing table|nil
---@param name string # the key loading stored it under
---@param build fun(): table
---@return table
local function inheritSky(existing, name, build)
    local layer = existing or Assets.get(name) or build()
    layer.alpha = 1 -- loading may have handed it over mid-fade
    return layer
end

--- records the answer so the prompt is never asked twice, and applies it now
---@param enabled boolean
function MainMenu:saveStatsConsent(enabled)
    local settings = Settings.load()
    settings.shareStats = enabled
    settings.statsConsentAsked = true
    Settings.save(settings)
    Stats.setEnabled(enabled)
    self.statsConsentDialog:close()
end

--- Decline is listed first, so pressing Enter reflexively can't opt someone in
function MainMenu:buildStatsConsentDialog()
    if self.statsConsentDialog then return end

    self.statsConsentDialog = UI.Dialog.new{
        title = function() return I18n.t("menu.statsConsent.title") end,
        message = function() return I18n.t("menu.statsConsent.message") end,
        buttons = {
            { label = function() return I18n.t("menu.statsConsent.decline") end,
              onSelect = function() self:saveStatsConsent(false) end },
            { label = function() return I18n.t("menu.statsConsent.accept") end,
              onSelect = function() self:saveStatsConsent(true) end },
        },
        --- Escape and clicking the scrim are explicit declines rather than a
        -- way to postpone the question and accidentally enable collection.
        onCancel = function() self:saveStatsConsent(false) end,
    }
    self.statsConsentDialog:setFocusSound(UI.Sfx.focus)
end

--- rebuilds what depends on the window and inherits what the loading screen
-- already made; the menu itself is stateless between visits and built once
---@param previousName string|nil # the entrance animation only plays coming from loading
function MainMenu:enter(previousName)
    UI.Music.start()
    self.title = buildTitle()
    self.version = buildVersionLabel()
    self.onlineCount = Stats.online
    self.onlinePlayers = buildOnlinePlayersLabel(self.onlineCount)
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

    self.splash = self.splash or Splash.pick()

    if not self.menu then -- stateless between visits, so build it just once
        self.menu = Menu.new({
            { label = function() return I18n.t("menu.play") end, onSelect = function()
                UI.Sfx.select()
                StateManager.fadeTo("play")
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

    if previousName == "loading" then
        self.menu:playIntro()
    end

    Presence.set{ details = "Main Menu", state = "Getting ready",
                  smallText = "In the menu" }

    self:layout()

    self:buildStatsConsentDialog()
    if not Settings.load().statsConsentAsked then
        self.statsConsentDialog:openDialog()
    else
        self.statsConsentDialog:close()
    end
end

--- the title, the corner links and labels, and the menu column
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
    if self.statsConsentDialog then self.statsConsentDialog:layout() end
end

--- rebuilds the online-players label when the figure changes, which is why it
-- re-lays out from here
---@param dt number
function MainMenu:update(dt)
    self.nebula:update(dt)
    self.stars:update(dt)
    self.starfield:update(dt)
    self.title:update(dt)
    self.splash:update(dt)
    self.menu:update(dt)
    if self.statsConsentDialog:isOpen() then
        self.statsConsentDialog:update(dt)
    end

    if Stats.online ~= self.onlineCount then
        self.onlineCount = Stats.online
        self.onlinePlayers = buildOnlinePlayersLabel(self.onlineCount)
        self:layout()
    end
end

---@param w number
---@param h number
---@param rescaled boolean # the UI scale changed too, so the corner labels need rebuilding at the new font size
function MainMenu:resize(w, h, rescaled)
    self.title = buildTitle()
    if rescaled then
        self.version = buildVersionLabel()
        self.onlinePlayers = buildOnlinePlayersLabel(self.onlineCount)
    end
    self:layout()
end

---@param key string
function MainMenu:keypressed(key)
    if self.statsConsentDialog:isOpen() then
        return self.statsConsentDialog:keypressed(key)
    end
    self.menu:keypressed(key)
end

--- true if the pointer is over any corner icon link -- used to color the cursor
---@return boolean
function MainMenu:anyLinkHover()
    for _, link in ipairs(self.links) do
        if link.hover then return true end
    end
    return false
end

---@param x number
---@param y number
function MainMenu:mousemoved(x, y)
    if self.statsConsentDialog:isOpen() then
        self.statsConsentDialog:mousemoved(x, y)
        self.mouseX, self.mouseY = x, y
        return
    end
    self.menu:mousemoved(x, y)
    for _, link in ipairs(self.links) do link:mousemoved(x, y) end
    self.mouseX, self.mouseY = x, y
end

--- routed in order: dialog, menu, corner links, then the sky -- so a click only
-- pops a star when it landed on nothing else
---@param x number
---@param y number
---@param button integer
function MainMenu:mousepressed(x, y, button)
    if self.statsConsentDialog:isOpen() then
        return self.statsConsentDialog:mousepressed(x, y, button)
    end
    if self.menu:mousepressed(x, y, button) then return end -- UI wins the click; only empty sky reaches the starfield
    for _, link in ipairs(self.links) do
        if link:mousepressed(x, y, button) then return end
    end

    local hit, golden, rainbow = self.starfield:mousepressed(x, y, button)
    if not hit then return end -- a click on empty sky is not a pop
    Stats.pop(rainbow and "rainbow" or golden and "golden" or "normal")
end

---@param x number
---@param y number
---@param button integer
function MainMenu:mousereleased(x, y, button)
    if self.statsConsentDialog:isOpen() then
        return self.statsConsentDialog:mousereleased(x, y, button)
    end
    self.menu:mousereleased(x, y, button)
    for _, link in ipairs(self.links) do link:mousereleased(x, y, button) end
end

--- back to front: nebula, stars, shooting stars, corner chrome, title, splash,
-- menu, and the consent dialog over everything
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

    if self.statsConsentDialog:isOpen() then
        self.statsConsentDialog:draw()
        local hover = self.statsConsentDialog:hovering(self.mouseX or -1, self.mouseY or -1)
        UI.Cursor.setHover(hover)
        return
    end

    local overMenu, dangerous = self.menu:hovering(self.mouseX or -1, self.mouseY or -1)
    UI.Cursor.setHover(self.mouseX ~= nil and (self:anyLinkHover() or overMenu), dangerous)
end

return MainMenu
