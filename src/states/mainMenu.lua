-- src/states/mainMenu.lua
-- Title screen: chroma title (via TextFactory) plus a keyboard/mouse menu of
-- themed buttons.

local StateManager  = require "core.stateManager"
local Assets        = require "core.assets"
local Presence      = require "services.presence"
local Menu          = require "ui.widgets.menu"
local TextFactory   = require "ui.text.textFactory"
local UI            = require "ui"
local I18n          = require "core.i18n"
local Particles     = require "particles"
local DiscordMark   = require "ui.icons.discordMark"
local GithubMark    = require "ui.icons.githubMark"
local GameTitle     = require "ui.text.gameTitle"
local Audio         = require "core.audio"
local Audios        = require "utils.audios"
local Globals       = require "globals"

local Stats         = require "services.stats"

-- Layout is expressed as fractions of the window so it survives resizing and
-- runs at any resolution, instead of hardcoded pixel offsets. The title's ratio
-- lives in gameTitle.lua, since the loading screen animates to it.
local MENU_Y_RATIO = 0.44

-- Repo that the clickable GitHub mark opens.
local GITHUB_URL = "https://github.com/kwlew/TD-Idle"
local DISCORD_URL = "https://discord.gg/HEQ9PB5UHq"
-- Side length of the GitHub mark in the bottom-left corner, and the margin
-- around the bottom-corner furniture. Design-space px (see Theme.px).
local GITHUB_ICON_SIZE = 26
local DISCORD_ICON_SIZE = 26
local CORNER_PAD = 12

local MainMenu = {}

-- Rebuilt on enter/resize so its wrap width matches the current window and the
-- text stays horizontally centered. Shared with the loading screen, which eases
-- its own copy into this exact pose on the way here.
local buildTitle = GameTitle.build

-- A small dim standalone label, positioned bottom-right in draw (no position
-- baked in here so it can track window resizes).
local function buildVersionLabel()
    return TextFactory:new{
        text = "v" .. Globals.game.version,
        font = UI.Theme.font("small"),
        color = UI.Theme.colors.textDim,
    }
end


local function grouped(n)
    local sep = I18n.t("format.thousands")
    local text = tostring(math.floor(n))
    local done
    repeat
        text, done = text:gsub("^(%-?%d+)(%d%d%d)", "%1" .. sep .. "%2")
    until done == 0
    return text
end

-- A small dim standalone label for the bottom-right stack. Shared by the two
-- world figures so they get identical treatment.
local function buildCornerLabel(text)
    return TextFactory:new{
        text = text,
        font = UI.Theme.font("small"),
        color = UI.Theme.colors.textDim,
    }
end

local function buildOnlinePlayersLabel(count)
    if not count then return nil end
    return buildCornerLabel(I18n.t("menu.onlinePlayers", { n = grouped(count) }))
end

local function buildStarsPoppedLabel(stars, golden)
    if not stars then return nil end
    return buildCornerLabel(I18n.t("menu.starsPopped", {
        n = grouped(stars),
        g = grouped(golden or 0),
    }))
end

local function inheritSky(existing, name, build)
    local layer = existing or Assets.get(name) or build()
    layer.alpha = 1 -- loading may have handed it over mid-fade
    return layer
end

local function menuMusic()
    local source = Audios.get("mainMenuBG")
    if not source or source:isPlaying() then return end
    Audio.play("music", source, { loop = true })
end

function MainMenu:enter()
    menuMusic()
    self.title = buildTitle()
    self.version = buildVersionLabel()
    self.onlineCount = Stats.online
    self.starCount, self.goldenCount = Stats.stars, Stats.golden
    self.onlinePlayers = buildOnlinePlayersLabel(self.onlineCount)
    self.starsPopped = buildStarsPoppedLabel(self.starCount, self.goldenCount)
    self.discordHover = false
    self.discordPressed = false
    self.githubHover = false
    self.githubPressed = false
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

    -- The menu itself is stateless between visits, so build it just once.
    if not self.menu then
        self.menu = Menu.new({
            -- Options button
            { label = function() return I18n.t("menu.options") end, onSelect = function()
                UI.Sfx.select()
                StateManager.fadeTo("options", { returnTo = "mainMenu" })
            end },
            -- Quit button
            { label = function() return I18n.t("menu.quit") end, danger = true,
              onSelect = function()
                love.event.quit()
            end },
        })
        self.menu:onFocusChanged(UI.Sfx.focus)
    end

    Presence.set{ details = "Main Menu", state = "Getting ready",
                  smallText = "In the menu" }

    self:layout()
end

-- Computes every rect this screen draws.
function MainMenu:layout()
    local w, h = love.graphics.getDimensions()
    local pad = UI.Theme.px(CORNER_PAD)
    local iconSize = UI.Theme.px(GITHUB_ICON_SIZE)
    local discordIconSize = UI.Theme.px(DISCORD_ICON_SIZE)

    self.title.y = h * GameTitle.MENU_Y_RATIO
    self.githubBounds = { x = pad, y = h - iconSize - pad, w = iconSize, h = iconSize }
    self.discordBound = { x = pad, y = h - iconSize - pad - discordIconSize - pad, w = discordIconSize, h = discordIconSize }


    local stack = { self.version }
    if self.onlinePlayers then stack[#stack + 1] = self.onlinePlayers end
    if self.starsPopped then stack[#stack + 1] = self.starsPopped end

    local y = h - pad
    for _, label in ipairs(stack) do
        y = y - label.font:getHeight()
        label:setPosition(w - label.font:getWidth(label.text) - pad, y)
    end

    self.menu:layout(h * MENU_Y_RATIO)
end

function MainMenu:update(dt)
    self.nebula:update(dt)
    self.stars:update(dt)
    self.starfield:update(dt)
    self.title:update(dt)
    self.menu:update(dt)

    local moved = false

    if Stats.online ~= self.onlineCount then
        self.onlineCount = Stats.online
        self.onlinePlayers = buildOnlinePlayersLabel(self.onlineCount)
        moved = true
    end

    if Stats.stars ~= self.starCount or Stats.golden ~= self.goldenCount then
        self.starCount, self.goldenCount = Stats.stars, Stats.golden
        self.starsPopped = buildStarsPoppedLabel(self.starCount, self.goldenCount)
        moved = true
    end

    if moved then self:layout() end
end

-- Widgets resolve their fonts per draw.
function MainMenu:resize(w, h, rescaled)
    self.title = buildTitle()
    if rescaled then
        self.version = buildVersionLabel()
        self.onlinePlayers = buildOnlinePlayersLabel(self.onlineCount)
        self.starsPopped = buildStarsPoppedLabel(self.starCount, self.goldenCount)
    end
    self:layout()
end

function MainMenu:keypressed(key)
    self.menu:keypressed(key)
end

-- Hit test for the clickable GitHub mark.
function MainMenu:githubContains(x, y)
    local b = self.githubBounds
    return b ~= nil and UI.Theme.pointIn(x, y, b.x, b.y, b.w, b.h)
end

-- Hit test for the clickable Discord mark.
function MainMenu:discordContains(x, y)
    local b = self.discordBound
    return b ~= nil and UI.Theme.pointIn(x, y, b.x, b.y, b.w, b.h)
end

function MainMenu:mousemoved(x, y)
    self.menu:mousemoved(x, y)
    self.githubHover = self:githubContains(x, y)
    self.discordHover = self:discordContains(x, y)
    -- The cursor itself is requested from draw.
    self.mouseX, self.mouseY = x, y
end

function MainMenu:mousepressed(x, y, button)
    -- UI wins the click; only clicks on empty sky reach the starfield.
    if self.menu:mousepressed(x, y, button) then return end
    if button == 1 and self:githubContains(x, y) then
        self.githubPressed = true
        UI.Sfx.press()
        return
    end
    if button == 1 and self:discordContains(x, y) then
        self.discordPressed = true
        UI.Sfx.press()
        return
    end

    local hit, golden, rainbow = self.starfield:mousepressed(x, y, button)
    if hit then
        Stats.pop(golden)
        -- TODO: Stats.pop only distinguishes golden vs not right now. Once it
        -- can track a third category, count rainbow pops here too:
        -- if rainbow then Stats.popRainbow() end
    end
end

function MainMenu:mousereleased(x, y, button)
    self.menu:mousereleased(x, y, button)
    -- Open the repo only on a full press+release on the mark, so a click that
    -- starts elsewhere or drags off doesn't fire it.
    if button == 1 and self.githubPressed then
        self.githubPressed = false
        if self:githubContains(x, y) then
            love.system.openURL(GITHUB_URL)
        end
    end
    if button == 1 and self.discordPressed then
        self.discordPressed = false
        if self:discordContains(x, y) then
            love.system.openURL(DISCORD_URL)
        end
    end
end

-- Draw only. Every rect here was computed by MainMenu:layout().
function MainMenu:draw()
    self.nebula:draw()

    self.stars:draw()

    self.starfield:draw()

    self.version:draw()

    if self.onlinePlayers then
        self.onlinePlayers:draw()
    end
    if self.starsPopped then
        self.starsPopped:draw()
    end

    local mark = self.githubBounds
    GithubMark.draw(mark.x, mark.y, mark.w,
        self.githubHover and {0.80, 0.80, 0.80} or UI.Theme.colors.textDim,
        self.githubHover and 1 or 0.45)
    

    local discordMark = self.discordBound
    DiscordMark.draw(discordMark.x, discordMark.y, discordMark.w,
        self.discordHover and {0.80, 0.80, 0.80} or UI.Theme.colors.textDim,
        self.discordHover and 1 or 0.45)

    self.title:drawChroma()

    self.menu:draw()

    UI.Label.hint(I18n.t("menu.hint"), true)

    -- self.githubHover never carries danger — the mark is a plain link, not a
    -- destructive action — so the menu's own flag is what decides the color.
    local overMenu, dangerous = self.menu:hovering(self.mouseX or -1, self.mouseY or -1)
    UI.Cursor.setHover(self.mouseX ~= nil and (self.githubHover or overMenu), dangerous)
end

return MainMenu
