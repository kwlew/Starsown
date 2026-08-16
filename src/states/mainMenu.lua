-- src/states/mainMenu.lua
-- Title screen: chroma title (via TextFactory) plus a keyboard/mouse menu of
-- themed buttons.

local StateManager  = require "core.stateManager"
local Assets        = require "core.assets"
local Presence      = require "services.presence"
local Menu          = require "ui.menu"
local TextFactory   = require "ui.textFactory"
local UI            = require "ui"
local I18n          = require "core.i18n"
local Particles     = require "particles"
local GithubMark    = require "ui.githubMark"
local GameTitle     = require "ui.gameTitle"
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

-- Groups a number for display: 1234567 -> "1,234,567", using whatever separator
-- the active language uses (a comma in English, a period in Spanish and
-- Portuguese). The world star tally is the one number here that gets long
-- enough to be unreadable ungrouped.
local function grouped(n)
    local sep = I18n.t("format.thousands")
    local text = tostring(math.floor(n))
    -- Walk right to left in threes. The %1 guard stops the pattern from
    -- prefixing a separator onto the leading group.
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

-- Sits just above the version label. Returns nil when the count is unknown — no
-- server response yet, no network, or the player opted out — and every caller
-- treats nil as "draw nothing". A counter that says 0 (or "--") makes a live
-- game look abandoned, which is worse than not showing one at all.
local function buildOnlinePlayersLabel(count)
    if not count then return nil end
    return buildCornerLabel(I18n.t("menu.onlinePlayers", { n = grouped(count) }))
end

-- The world star tally, above the player count. Same nil rule. Golden stars are
-- a subset of the total, not a second pile added to it, which is why the string
-- reads "of which" rather than listing two independent numbers.
local function buildStarsPoppedLabel(stars, golden)
    if not stars then return nil end
    return buildCornerLabel(I18n.t("menu.starsPopped", {
        n = grouped(stars),
        g = grouped(golden or 0),
    }))
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
    -- Cached alongside the labels so update() can tell when the heartbeat has
    -- actually moved a number. Re-read on every enter because they may have
    -- arrived (or been switched off in Options) while we were away.
    self.onlineCount = Stats.online
    self.starCount, self.goldenCount = Stats.stars, Stats.golden
    self.onlinePlayers = buildOnlinePlayersLabel(self.onlineCount)
    self.starsPopped = buildStarsPoppedLabel(self.starCount, self.goldenCount)
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

    -- The bottom-right stack, laid out from the floor upwards and right-aligned
    -- to a shared margin. Built as a list rather than three hardcoded offsets
    -- because the two world figures come and go independently — either can be
    -- absent while the count is unknown, and a gap where one used to be would
    -- leave the version label floating.
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

    -- The figures land from the heartbeat thread, at most once every few
    -- minutes. TextFactory bakes a glyph mesh, so a label is rebuilt only when
    -- its number actually changes rather than every frame — and re-laid out
    -- with it, because a different number is a different width and the whole
    -- stack is right-aligned.
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

-- Widgets resolve their fonts per draw, but TextFactory caches a glyph mesh
-- built from the font it was handed, so both of these have to be rebuilt by
-- hand whenever the UI scale changes (and the title on any resize, since its
-- wrap width is the window width).
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
    -- A popped star is the one thing on this screen that feeds the world
    -- tally. Recording it is two integers on the main thread; it rides out on
    -- the next heartbeat rather than costing a request of its own, and does
    -- nothing at all if the player has opted out.
    local hit, golden = self.starfield:mousepressed(x, y, button)
    if hit then Stats.pop(golden) end
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

    -- The world figures: same treatment, stacked above the version. Both are
    -- absent until the first heartbeat comes back, and gone again if the player
    -- opts out.
    if self.onlinePlayers then
        self.onlinePlayers:draw()
    end
    if self.starsPopped then
        self.starsPopped:draw()
    end

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
