-- src/states/mainMenu.lua
-- Title screen: chroma title (via TextFactory) plus a keyboard/mouse menu of
-- themed buttons.

local StateManager  = require "lib.stateManager"
local Assets        = require "lib.assets"
local Presence      = require "lib.presence"
local Menu          = require "lib.menu"
local TextFactory   = require "lib.textFactory"
local UI            = require "lib.ui"
local I18n          = require "lib.i18n"
local Particles     = require "lib.particles"
local GithubMark    = require "lib.ui.githubMark"
local GameTitle     = require "gameTitle"
local Audio         = require "lib.audio"
local Audios        = require "lib.utils.audios"
local Globals       = require "globals"

-- Layout is expressed as fractions of the window so it survives resizing and
-- runs at any resolution, instead of hardcoded pixel offsets. The title's ratio
-- lives in gameTitle.lua, since the loading screen animates to it.
local MENU_Y_RATIO = 0.44

-- Repo that the clickable GitHub mark opens.
local GITHUB_URL = "https://github.com/kwlew/TD-Idle"
-- Side length of the GitHub mark in the bottom-left corner, and the margin
-- around the bottom-corner furniture. Design-space px (see Theme.px).
local GITHUB_ICON_SIZE = 26
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

-- A background layer is built by the loading screen and handed over through
-- Assets, so it's already on screen behind the boot sequence and never pops in
-- here; `build` is the fallback for entering the menu without having come
-- through loading. Either way what we already have is kept: re-entering the menu
-- (e.g. back from Options) must not reshuffle the whole night sky.
local function inheritSky(existing, name, build)
    local layer = existing or Assets.get(name) or build()
    layer.alpha = 1 -- loading may have handed it over mid-fade
    return layer
end

-- Starts the preloaded menu track. enter() runs again every time we come back
-- here (from Options, from the game), so this checks the shared Source before
-- replaying it — otherwise a round trip through Options would stack a second
-- copy of the music on top of the first.
local function menuMusic()
    local source = Audios.get("mainMenuBG")
    if not source or source:isPlaying() then return end
    Audio.play("music", source, { loop = true })
end

function MainMenu:enter()
    menuMusic()
    self.title = buildTitle()
    self.version = buildVersionLabel()
    self.githubHover = false
    self.githubPressed = false
    -- Seeded from the real pointer so hover feedback is right on the first
    -- frame back from Options, before the player moves the mouse again.
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
    -- Labels are functions so they re-read the active language every draw; a
    -- language change from Options updates the menu with no rebuild.
    if not self.menu then
        self.menu = Menu.new({
            -- Play button
            { label = function() return I18n.t("menu.play") end, onSelect = function()
                Audio.stopAll() -- stop the menu music before the game starts
                UI.Sfx.select()
                -- Stamped here rather than in Game:enter so the run clock starts
                -- when Play was pressed, not when the fade finishes.
                StateManager.fadeTo("game")
            end },
            -- Achievements button
            { label = function() return I18n.t("menu.achievements") end, onSelect = function()
                UI.Sfx.select()
                StateManager.fadeTo("achievements")
            end },
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

    -- Options may have changed the resolution or the language while we were
    -- away, and both move things here (menu width is driven by label widths).
    self:layout()
end

-- Computes every rect this screen draws. Called on enter and on resize, never
-- from draw — the GitHub mark's hitbox and the menu's button bounds are read by
-- input handlers, which must not depend on a draw having happened first.
function MainMenu:layout()
    local w, h = love.graphics.getDimensions()
    local pad = UI.Theme.px(CORNER_PAD)
    local iconSize = UI.Theme.px(GITHUB_ICON_SIZE)

    self.title.y = h * GameTitle.MENU_Y_RATIO
    self.githubBounds = { x = pad, y = h - iconSize - pad, w = iconSize, h = iconSize }
    self.version:setPosition(
        w - self.version.font:getWidth(self.version.text) - pad,
        h - self.version.font:getHeight() - pad)

    self.menu:layout(h * MENU_Y_RATIO)
end

function MainMenu:update(dt)
    self.nebula:update(dt)
    self.stars:update(dt)
    self.starfield:update(dt)
    self.title:update(dt)
    self.menu:update(dt)
end

-- Widgets resolve their fonts per draw, but TextFactory caches a glyph mesh
-- built from the font it was handed, so both of these have to be rebuilt by
-- hand whenever the UI scale changes (and the title on any resize, since its
-- wrap width is the window width).
function MainMenu:resize(w, h, rescaled)
    self.title = buildTitle()
    if rescaled then
        self.version = buildVersionLabel()
    end
    self:layout()
end

function MainMenu:keypressed(key)
    self.menu:keypressed(key)
end

-- Hit test for the clickable GitHub mark. Its bounds are recomputed every draw
-- (see below), so this is nil-safe before the first frame.
function MainMenu:githubContains(x, y)
    local b = self.githubBounds
    return b ~= nil and UI.Theme.pointIn(x, y, b.x, b.y, b.w, b.h)
end

function MainMenu:mousemoved(x, y)
    self.menu:mousemoved(x, y)
    self.githubHover = self:githubContains(x, y)
    -- The cursor itself is requested from draw, not here: mousemoved stops
    -- firing the moment the player holds still, so setting it here would drop
    -- the hand as soon as they stopped moving over the mark.
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
    self.starfield:mousepressed(x, y, button)
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
end

-- Draw only. Every rect here was computed by MainMenu:layout().
function MainMenu:draw()
    -- Back to front: gas, then the fixed sky on top of it, then the shooting
    -- stars in front of both.
    self.nebula:draw()

    self.stars:draw()

    self.starfield:draw()

    -- Version: a plain standalone label pinned to the bottom-right.
    self.version:draw()

    -- GitHub mark: bottom-left, a link to the repo that lights up on hover.
    -- Always carries a soft halo so it reads against the starfield, and lights
    -- up to the accent color with a stronger glow while hovered.
    local mark = self.githubBounds
    GithubMark.draw(mark.x, mark.y, mark.w,
        self.githubHover and UI.Theme.colors.accent or UI.Theme.colors.text,
        self.githubHover and 1 or 0.45)

    self.title:drawChroma()

    self.menu:draw()

    -- Shadowed: this sits directly on the starfield, where dim grey text
    -- crossing a bright star or a constellation line stops being readable.
    UI.Label.hint(I18n.t("menu.hint"), true)

    -- Asked for every frame the cursor is over something clickable (see
    -- UI.Cursor for why this can't live in mousemoved).
    if self.mouseX and (self.githubHover or self.menu:hovering(self.mouseX, self.mouseY)) then
        UI.Cursor.want("hand")
    end
end

return MainMenu
