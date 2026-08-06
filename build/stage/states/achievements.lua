-- src/states/achievements.lua
-- Achievement browser: one tab per category, a tree of icon tiles showing what
-- unlocks what, and a detail panel for whatever is selected.
--
-- Why tiles and a panel rather than titles written into the nodes: a node wide
-- enough to hold "Fifty and Counting" is ~160px, which spreads even a small tree
-- across the whole window and leaves its shape unreadable. Shrinking the node to
-- its icon makes the tree dense enough that the *shape* of a branch — how deep
-- it goes, where it forks — reads at a glance, which is the only reason to draw
-- a tree instead of a list. The text has to go somewhere, so it goes in a panel
-- beside it, which is also where an idle game's real payload lives: what the
-- achievement is worth.
--
-- Selection is one concept shared by both input devices — hovering a tile
-- selects it, and so do the arrow keys — so the panel always describes the thing
-- the player is pointing at, however they're pointing.
--
-- PLACEHOLDER. The tree below is invented content standing in for the real
-- thing; nothing is wired to game state, and `unlocked` is hardcoded so every
-- node state is visible while the screen is being designed. When achievements
-- become real:
--
--   * move titles, descriptions and rewards into assets/lang/*.json, the way
--     categories already are (all three may be functions — see nodeText);
--   * replace `unlocked` with a lookup against saved progress;
--   * have `reward` mean something to the game rather than just read well.
--
-- TODO: after the initial game implementation, start achievement implementation.

local StateManager = require "lib.stateManager"
local Presence     = require "lib.presence"
local I18n         = require "lib.i18n"
local Math         = require "lib.utils.math"
local UI           = require "lib.ui"

local Achievements = {}

local HEADING_Y_RATIO = 0.09

-- Design-space px, scaled through Theme.px at use.
local CONTENT_MAX_W = 1120
local DETAIL_W      = 380 -- the panel beside the tree
local PANEL_GAP     = 16
local TILE          = 68  -- a node is a square icon tile
local COL_GAP       = 52  -- horizontal space between tree depths
local ROW_GAP       = 28  -- vertical space between sibling rows
local VIEW_PAD      = 20  -- inside the tree panel, around the tree
local DETAIL_PAD    = 20
local DETAIL_ICON   = 52
local BAR_H         = 16
local WHEEL_STEP    = 48  -- px panned per wheel notch

-- How much of the accent an "available" node carries — one whose parent is
-- earned but which isn't yet. It sits deliberately between earned and locked,
-- because "what can I go do next" is the question this screen exists to answer.
local AVAILABLE_MIX = 0.45

-- The categories, in tab order. Each is a tree of nodes:
--
--   id       : unique within the category; the save key a real one would use
--   icon     : a lib/ui/glyph name
--   title    : string, or function -> string once these are localized
--   desc     : what earning it takes
--   reward   : what it's worth — the reason an idle player is on this screen
--   kind     : "normal" | "goal" | "challenge", which picks the tile's frame,
--              exactly as Minecraft's advancement frames do
--   unlocked : earned. A node whose parent is earned is "available"
--   secret   : hidden until earned — shown as a locked tile with no title
--   children : the entries this one unlocks
--
-- Category names are localized (achievements.category.<id>); node text is not
-- yet, since none of it is final.
local CATEGORIES = {
    {
        id = "foundations",
        root = {
            id = "groundBroken", icon = "tower", kind = "goal", unlocked = true,
            title = "Ground Broken", desc = "Place your first tower.",
            reward = "+2% tower damage",
            children = {
                {
                    id = "holdTheLine", icon = "shield", unlocked = true,
                    title = "Hold the Line", desc = "Survive your first wave.",
                    reward = "+1 starting life",
                    children = {
                        {
                            id = "tenWaves", icon = "wave",
                            title = "Ten Waves Deep", desc = "Reach wave 10.",
                            reward = "+5% gold per wave",
                            children = {
                                { id = "fiftyWaves", icon = "crosshair", kind = "challenge",
                                  title = "Fifty and Counting", desc = "Reach wave 50.",
                                  reward = "+15% gold per wave" },
                            },
                        },
                        { id = "flawless", icon = "star",
                          title = "Not a Scratch", desc = "Clear a wave without losing a life.",
                          reward = "+1 starting life" },
                    },
                },
                {
                    id = "reinforced", icon = "gear",
                    title = "Reinforced", desc = "Upgrade a tower to level 2.",
                    reward = "-5% upgrade cost",
                    children = {
                        { id = "maxed", icon = "trophy", kind = "goal",
                          title = "Fully Loaded", desc = "Take a tower to its maximum level.",
                          reward = "-10% upgrade cost" },
                    },
                },
            },
        },
    },
    {
        id = "arsenal",
        root = {
            id = "armory", icon = "gear", kind = "goal", unlocked = true,
            title = "Armory Opened", desc = "Unlock a second tower type.",
            reward = "Unlocks the build menu",
            children = {
                { id = "cannon", icon = "flame", unlocked = true,
                  title = "Splash Damage", desc = "Build your first cannon.",
                  reward = "+5% splash radius" },
                {
                    id = "frost", icon = "frost",
                    title = "Slow and Steady", desc = "Build your first frost tower.",
                    reward = "+5% slow duration",
                    children = {
                        { id = "deepFreeze", icon = "frost", kind = "challenge",
                          title = "Deep Freeze", desc = "Hold 100 enemies frozen at once.",
                          reward = "+20% slow duration" },
                    },
                },
                {
                    id = "sniper", icon = "crosshair",
                    title = "Sniper's Nest", desc = "Build your first long-range tower.",
                    reward = "+5% tower range",
                    children = {
                        { id = "longShot", icon = "star",
                          title = "One Shot", desc = "Kill an enemy from across the map.",
                          reward = "+10% critical chance" },
                    },
                },
            },
        },
    },
    {
        id = "economy",
        root = {
            id = "pocketChange", icon = "coin", kind = "goal", unlocked = true,
            title = "Pocket Change", desc = "Earn your first 100 gold.",
            reward = "+2% gold gain",
            children = {
                {
                    id = "interest", icon = "clock", unlocked = true,
                    title = "Compound Interest", desc = "Earn gold while the game is closed.",
                    reward = "+1 hour of offline earnings",
                    children = {
                        { id = "overnight", icon = "clock", kind = "goal",
                          title = "Overnight Fortune", desc = "Collect a full offline cycle.",
                          reward = "+4 hours of offline earnings" },
                    },
                },
                {
                    id = "prestige", icon = "star",
                    title = "Fresh Start", desc = "Reset your progress for the first time.",
                    reward = "+10% permanent gold gain",
                    children = {
                        { id = "secondWind", icon = "wave",
                          title = "Second Wind", desc = "Reach wave 10 after a reset.",
                          reward = "+5% starting gold" },
                        { id = "endlessLoop", icon = "gear", kind = "challenge",
                          title = "Endless Loop", desc = "Reset ten times.",
                          reward = "+50% permanent gold gain" },
                    },
                },
            },
        },
    },
    {
        id = "conquest",
        root = {
            id = "firstBlood", icon = "crosshair", kind = "goal", unlocked = true,
            title = "First Blood", desc = "Defeat 100 enemies.",
            reward = "+2% tower damage",
            children = {
                {
                    id = "bossSlayer", icon = "shield",
                    title = "Boss Slayer", desc = "Defeat your first boss.",
                    reward = "+10% damage to bosses",
                    children = {
                        { id = "untouchable", icon = "trophy", kind = "challenge",
                          title = "Untouchable", desc = "Defeat a boss without taking damage.",
                          reward = "+30% damage to bosses" },
                    },
                },
                {
                    id = "exterminator", icon = "flame",
                    title = "Exterminator", desc = "Defeat 10,000 enemies.",
                    reward = "+5% tower damage",
                    children = {
                        { id = "legend", icon = "trophy", kind = "goal",
                          title = "Legend", desc = "Defeat 1,000,000 enemies.",
                          reward = "+25% tower damage" },
                    },
                },
            },
        },
    },
    {
        id = "secrets",
        root = {
            id = "curious", icon = "star", kind = "goal", unlocked = true,
            title = "Curious", desc = "Find something you weren't meant to.",
            reward = "Bragging rights",
            children = {
                {
                    id = "stargazer", icon = "star", unlocked = true,
                    title = "Stargazer", desc = "Pop a shooting star on the title screen.",
                    reward = "bread",
                    children = {
                        { id = "goldenHour", icon = "coin", kind = "challenge", secret = true,
                          title = "Golden Hour", desc = "Pop a golden star.",
                          reward = "+10% gold gain" },
                    },
                },
                { id = "nightOwl", icon = "clock", secret = true,
                  title = "Night Owl", desc = "Leave the game running until sunrise.",
                  reward = "+2 hours of offline earnings" },
                { id = "completionist", icon = "trophy", kind = "challenge",
                  title = "Completionist", desc = "Earn every other achievement.",
                  reward = "A very shiny title screen" },
            },
        },
    },
}

-- Node text may be a plain string or a function, so moving it into the locale
-- files later needs no change here (the same contract every widget label uses).
local function nodeText(value) return UI.Theme.resolveLabel(value) end

-- A secret stays a blank until it's earned: its title, description and reward
-- are all withheld, which is the whole point of marking one.
local function isHidden(node)
    return node.secret and not node.unlocked
end

-- Flattens one category into a list of entries carrying each node's grid
-- position: column is its depth, and rows are handed to leaves in declaration
-- order. A parent then centers on the block of children beneath it, which is
-- what makes a branch's trunk line up with the middle of what it feeds.
--
-- Built once per category and cached on it: the shape of a tree never changes,
-- only where it lands on screen (see Achievements:layoutTree).
local function placement(category)
    if category.entries then return category end

    local entries, nextRow, maxCol, earned = {}, 0, 0, 0

    local function walk(node, parent, depth)
        local entry = {
            node = node,
            parent = parent,
            col = depth,
            -- Earned, or the first rung above what's earned. Only a node whose
            -- parent is done is reachable, so this is exactly "what's next".
            available = not node.unlocked and (parent == nil or parent.node.unlocked),
        }
        entries[#entries + 1] = entry
        maxCol = math.max(maxCol, depth)
        if node.unlocked then earned = earned + 1 end

        local children = node.children
        if not children or #children == 0 then
            entry.row = nextRow
            nextRow = nextRow + 1
        else
            local first, last
            for _, child in ipairs(children) do
                local placed = walk(child, entry, depth + 1)
                first = first or placed.row
                last = placed.row
            end
            entry.row = (first + last) / 2
        end
        return entry
    end

    walk(category.root, nil, 0)

    category.entries = entries
    category.cols = maxCol + 1
    category.rows = nextRow
    category.earned = earned
    return category
end

-- Earned and total across every category, for the completion bar.
local function totalProgress()
    local done, total = 0, 0
    for _, category in ipairs(CATEGORIES) do
        placement(category)
        done, total = done + category.earned, total + #category.entries
    end
    return done, total
end

-- Keeps a pan offset inside the slack between the content and its viewport. A
-- tree smaller than the viewport has no slack at all, so it stays centered and
-- can't be shoved off the edge.
local function clampPan(pan, content, viewport)
    local slack = content - viewport
    if slack <= 0 then return 0 end
    return Math.clamp(pan, -slack / 2, slack / 2)
end

--------------------------------------------------------------------------------
-- The tree viewport, as a widget
--------------------------------------------------------------------------------

-- Making the tree a Widget rather than a hand-rolled region buys three things
-- the focus group already implements: it takes its turn in the focus order like
-- any row, a press on it can capture the mouse so a pan keeps tracking off the
-- panel, and hover routing arrives for free. Everything it's asked to do it
-- hands straight back to the screen, which owns the tree's state.
local TreePane = {}
UI.Widget.extend(TreePane)

function TreePane.new(owner)
    local pane = UI.Widget.new(TreePane, {})
    pane.owner = owner
    return pane
end

function TreePane:mousepressed(px, py, button)
    if button ~= 1 or not self:contains(px, py) then return false end
    self.owner:beginPan(px, py)
    return true -- capture: a pan has to keep tracking once the cursor leaves
end

function TreePane:mousemoved(px, py)
    self.owner:panTo(px, py)
end

function TreePane:mousereleased()
    self.owner:endPan()
end

function TreePane:draw()
    self.owner:drawTree()
end

--------------------------------------------------------------------------------

function Achievements:activeCategory()
    return placement(CATEGORIES[self.tabBar.index])
end

-- Computes every rect this screen draws. Called on enter, on resize, and on tab
-- switch — never from draw, since hit-testing reads these.
--
-- The panels are the flexible piece: heading and tabs are pinned to the top, the
-- completion bar, Back button and hint to the bottom, and the panels take
-- whatever is left. That way the screen fits any window without the stack having
-- to be nudged around.
function Achievements:layout()
    local w, h = love.graphics.getDimensions()
    local m = UI.Theme.metrics

    local contentW = math.min(UI.Theme.px(CONTENT_MAX_W), w * 0.92)
    local contentX = (w - contentW) / 2

    local top = h * HEADING_Y_RATIO + UI.Theme.font("heading"):getHeight() + m.rowGap
    self.tabBar:setBounds(contentX, top, contentW, m.rowHeight)

    -- Bottom furniture, measured upward from the hint line: Back, then the
    -- completion bar, then its caption above that (the loading screen captions
    -- its bar the same way, and for the same reason — a line under the bar would
    -- be squeezed against whatever comes next).
    local barH = UI.Theme.px(BAR_H)
    local captionH = UI.Theme.font("small"):getHeight()
    local backY = UI.Label.hintY() - m.rowGap - m.rowHeight
    self.backButton:setBounds(contentX, backY, contentW, m.rowHeight)
    self.barRect = { x = contentX, y = backY - m.rowGap - barH, w = contentW, h = barH }
    self.captionY = self.barRect.y - UI.Theme.px(4) - captionH

    local panelY = top + m.rowHeight + m.rowGap
    local panelH = math.max(UI.Theme.px(200), self.captionY - m.rowGap - panelY)

    -- The detail panel keeps a fixed share; the tree takes the rest, so a wider
    -- window grows the tree rather than the paragraph beside it.
    local detailW = math.min(UI.Theme.px(DETAIL_W), contentW * 0.38)
    local gap = UI.Theme.px(PANEL_GAP)

    self.treePane:setBounds(contentX, panelY, contentW - detailW - gap, panelH)
    self.detail = { x = contentX + contentW - detailW, y = panelY, w = detailW, h = panelH }

    self:layoutTree()
end

-- Places the active category's tiles in window coordinates. Separate from
-- layout() because a tab switch changes the tree without moving anything else.
function Achievements:layoutTree()
    local category = self:activeCategory()
    local view = self.treePane
    local pad = UI.Theme.px(VIEW_PAD)

    local tile = UI.Theme.px(TILE)
    local colStep = tile + UI.Theme.px(COL_GAP)
    local rowStep = tile + UI.Theme.px(ROW_GAP)

    local contentW = (category.cols - 1) * colStep + tile
    local contentH = (category.rows - 1) * rowStep + tile
    local innerW, innerH = view.w - pad * 2, view.h - pad * 2

    self.panX = clampPan(self.panX, contentW, innerW)
    self.panY = clampPan(self.panY, contentH, innerH)
    self.contentW, self.contentH = contentW, contentH

    -- Centered in the viewport, then shifted by the pan. A tree that fits is
    -- simply centered, since clampPan pinned the offset to zero.
    local originX = view.x + pad + (innerW - contentW) / 2 + self.panX
    local originY = view.y + pad + (innerH - contentH) / 2 + self.panY

    for _, entry in ipairs(category.entries) do
        entry.x = originX + entry.col * colStep
        entry.y = originY + entry.row * rowStep
        entry.w, entry.h = tile, tile
    end
end

function Achievements:resize()
    self:layout()
end

-- The tile under the cursor, or nil. Only tiles inside the viewport count: a
-- panned tree is clipped there, and something scrolled out of sight must not
-- still answer the mouse.
function Achievements:nodeAt(x, y)
    local view = self.treePane
    if not (view and view:contains(x, y)) then return nil end
    for _, entry in ipairs(self:activeCategory().entries) do
        if UI.Theme.pointIn(x, y, entry.x, entry.y, entry.w, entry.h) then
            return entry
        end
    end
    return nil
end

-- Pans just enough to bring the selection inside the viewport — for when the
-- tree outgrows its panel and the arrow keys walk off the visible edge.
function Achievements:revealSelected()
    local entry, view = self.selected, self.treePane
    if not entry then return end
    local pad = UI.Theme.px(VIEW_PAD)

    local dx = 0
    if entry.x < view.x + pad then
        dx = view.x + pad - entry.x
    elseif entry.x + entry.w > view.x + view.w - pad then
        dx = (view.x + view.w - pad) - (entry.x + entry.w)
    end

    local dy = 0
    if entry.y < view.y + pad then
        dy = view.y + pad - entry.y
    elseif entry.y + entry.h > view.y + view.h - pad then
        dy = (view.y + view.h - pad) - (entry.y + entry.h)
    end

    if dx ~= 0 or dy ~= 0 then
        self.panX, self.panY = self.panX + dx, self.panY + dy
        self:layoutTree()
    end
end

-- Moves the selection to the nearest tile in a direction. Candidates have to lie
-- properly on that side; among them the closest wins, with drift across the axis
-- counted double so the selection prefers to travel in a straight line rather
-- than wander diagonally. Returns false when there is nothing that way, which is
-- how the arrow keys escape the tree (see keypressed).
function Achievements:moveSelection(dx, dy)
    local from = self.selected
    if not from then return false end
    local fx, fy = from.x + from.w / 2, from.y + from.h / 2

    local best, bestScore
    for _, entry in ipairs(self:activeCategory().entries) do
        if entry ~= from then
            local ex, ey = entry.x + entry.w / 2, entry.y + entry.h / 2
            local along = (ex - fx) * dx + (ey - fy) * dy
            local across = math.abs((ex - fx) * dy - (ey - fy) * dx)
            if along > 1 then
                local score = along + across * 2
                if not bestScore or score < bestScore then
                    best, bestScore = entry, score
                end
            end
        end
    end

    if not best then return false end
    self:select(best)
    self:revealSelected()
    return true
end

-- One selection shared by both input devices: hovering a tile selects it, and so
-- do the arrow keys, so the detail panel always describes whatever the player is
-- pointing at however they're pointing at it.
function Achievements:select(entry)
    if entry == self.selected then return end
    self.selected = entry
    UI.Sfx.focus()
end

function Achievements:selectTab(index)
    self.tabBar.index = index
    -- A new tree starts framed rather than wherever the last one was dragged to,
    -- with its root selected so the panel is never blank.
    self.panX, self.panY = 0, 0
    self:layoutTree()
    self.selected = self:activeCategory().entries[1]
end

function Achievements:beginPan(x, y)
    self.panFromX, self.panFromY = x, y
    self.panning = true
end

function Achievements:panTo(x, y)
    if not self.panning then
        -- Not a drag: this is hover routing, which is what keeps the panel
        -- following the cursor.
        local entry = self:nodeAt(x, y)
        if entry then self:select(entry) end
        return
    end
    self.panX = self.panX + (x - self.panFromX)
    self.panY = self.panY + (y - self.panFromY)
    self.panFromX, self.panFromY = x, y
    self:layoutTree()
end

function Achievements:endPan()
    self.panning = false
end

function Achievements:goBack()
    UI.Sfx.select()
    StateManager.fadeTo(self.returnTo)
end

-- StateManager calls enter(previousName, ...), so `opts` is whatever the caller
-- passed to switch(). Built like Options so the screen can later be opened from
-- inside a run as well as from the menu.
function Achievements:enter(previousName, opts)
    -- Re-asserted on every entry: the menu we came from set its own presence.
    Presence.set{ details = "Achievements", state = "Viewing achievements",
                  smallText = "In achievements" }

    self.returnTo = StateManager.returnTarget(previousName, opts, "achievements")

    self.mouseX, self.mouseY = love.mouse.getPosition()
    self.panning = false
    self.panX, self.panY = 0, 0
    self.time = 0

    if not self.group then
        self.group = UI.FocusGroup.new()
        self.group.onFocusChanged = UI.Sfx.focus
    end

    -- Built once; labels are functions so they re-read the active language every
    -- draw, and a language change needs no rebuild.
    if not self.tabBar then
        local tabs = {}
        for i, category in ipairs(CATEGORIES) do
            tabs[i] = function() return I18n.t("achievements.category." .. category.id) end
        end

        self.tabBar = UI.TabBar.new{
            tabs = tabs,
            onChange = function(_, index)
                UI.Sfx.select()
                self:selectTab(index)
            end,
        }

        self.treePane = TreePane.new(self)

        self.backButton = UI.Button.new{
            label = function() return I18n.t("achievements.back") end,
            onSelect = function() self:goBack() end,
        }

        -- Completion across every category — the number an idle player is
        -- actually here for. No percentage inside the bar: the "12 of 29"
        -- caption under it says the same thing in the units that matter.
        self.bar = UI.ProgressBar.new{ showPercent = false }

        self.group:setWidgets{ self.tabBar, self.treePane, self.backButton }
    end

    self:layout()
    self:selectTab(self.tabBar.index)

    -- Re-read on every visit rather than only on a tab switch: Options may have
    -- changed the language while we were away.
    local done, total = totalProgress()
    self.progressText = I18n.t("achievements.progress", { done = done, total = total })
    self.bar:setProgress(total > 0 and done / total or 0)
end

function Achievements:update(dt)
    self.time = self.time + dt -- drives the selection ring's pulse
    self.group:update(dt)
    self.bar:update(dt)
end

-- Arrow (and WASD) deltas, or nil for anything else.
local function arrowDelta(key)
    if key == "left"  or key == "a" then return -1, 0 end
    if key == "right" or key == "d" then return 1, 0 end
    if key == "up"    or key == "w" then return 0, -1 end
    if key == "down"  or key == "s" then return 0, 1 end
    return nil
end

function Achievements:keypressed(key)
    if key == "escape" then return self:goBack() end

    -- The tree owns the arrows while the focus is inside it, and hands them back
    -- only at its edges: pressing down past the last tile steps on to Back,
    -- exactly the way moving between rows works on every other screen. Trapping
    -- the focus outright would strand a keyboard player in the tree; spending
    -- the arrows on widget order would leave the tree unreachable without a
    -- mouse.
    if self.group:focused() == self.treePane then
        local dx, dy = arrowDelta(key)
        if dx and self:moveSelection(dx, dy) then return true end
    end

    return self.group:keypressed(key)
end

function Achievements:mousemoved(x, y)
    self.mouseX, self.mouseY = x, y
    self.group:mousemoved(x, y)
end

function Achievements:mousepressed(x, y, button)
    self.group:mousepressed(x, y, button)
end

function Achievements:mousereleased(x, y, button)
    self.group:mousereleased(x, y, button)
end

-- Vertical wheel scrolls the tree, shift-wheel scrolls it sideways — the tree
-- grows to the right, so sideways is the axis that runs out first.
function Achievements:wheelmoved(dx, dy)
    if not self.treePane:contains(self.mouseX or -1, self.mouseY or -1) then return end
    local step = UI.Theme.px(WHEEL_STEP)
    if love.keyboard.isDown("lshift", "rshift") then
        self.panX = self.panX + dy * step
    else
        self.panX = self.panX + dx * step
        self.panY = self.panY + dy * step
    end
    self:layoutTree()
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

-- Scratch for the one tile color that has to be mixed rather than named. Reused
-- rather than freshly allocated because this runs per tile per frame, and
-- Theme.lerp returns three scalars precisely so the draw path needn't allocate.
-- Safe to share: a tile's frame is drawn before the next one is computed.
local availableFrame = { 0, 0, 0 }

-- The frame color for a node's state, and the fill behind it. Earned nodes carry
-- the accent — or `warning` for a challenge, so the hardest entries stand apart
-- from the rest of a finished branch; available ones sit partway there; locked
-- ones are plain panel furniture.
local function nodeColors(entry)
    local c = UI.Theme.colors
    if entry.node.unlocked then
        return (entry.node.kind == "challenge") and c.warning or c.accent, c.accentDark
    end
    if entry.available then
        availableFrame[1], availableFrame[2], availableFrame[3] =
            UI.Theme.lerp(c.panelBorder, c.accent, AVAILABLE_MIX)
        return availableFrame, c.panel
    end
    return c.panelBorder, c.panel
end

-- Corner radius by frame kind, mirroring Minecraft's three advancement frames:
-- a plain box, a rounded "goal", and a hard-cornered "challenge".
local function nodeRadius(kind, size)
    if kind == "goal" then return size / 2 end
    if kind == "challenge" then return UI.Theme.px(2) end
    return UI.Theme.metrics.radius
end

-- The elbow from a parent's right edge into a child's left edge: out, across,
-- and in. Straight diagonals would cross each other into a mess as soon as a
-- branch has more than two children.
local function drawConnector(parent, child)
    local x1, y1 = parent.x + parent.w, parent.y + parent.h / 2
    local x2, y2 = child.x, child.y + child.h / 2
    local mid = (x1 + x2) / 2
    love.graphics.line(x1, y1, mid, y1, mid, y2, x2, y2)
end

function Achievements:drawNode(entry)
    local node = entry.node
    local frame, fill = nodeColors(entry)
    local radius = nodeRadius(node.kind, entry.h)
    local chosen = (self.selected == entry)

    if node.unlocked then
        UI.Theme.glowRect(entry.x, entry.y, entry.w, entry.h, radius,
            chosen and 1 or 0.5, frame)
    end

    UI.Theme.setColor(fill)
    love.graphics.rectangle("fill", entry.x, entry.y, entry.w, entry.h, radius, radius, 10)

    UI.Theme.setColor(frame, chosen and 1 or 0.75)
    love.graphics.rectangle("line", entry.x, entry.y, entry.w, entry.h, radius, radius, 10)

    -- The selection is a ring *outside* the tile, drawn in the accent rather
    -- than in the node's own color: a locked tile's frame is dim panel grey, and
    -- "slightly brighter grey" is not something you can pick out across a panel.
    -- It sits outside so the tile itself never moves or resizes — this is a map,
    -- and things on a map shouldn't shift when you point at them.
    if chosen then
        local grow = UI.Theme.px(5)
        UI.Theme.setColor(UI.Theme.colors.accent, UI.Theme.pulse(self.time))
        love.graphics.rectangle("line", entry.x - grow, entry.y - grow,
            entry.w + grow * 2, entry.h + grow * 2, radius + grow, radius + grow, 10)
    end

    -- A hidden node shows a lock instead of its own icon: revealing the picture
    -- would give away what it is, which is the one thing marking it secret buys.
    local icon = isHidden(node) and "lock" or node.icon
    local size = entry.w * 0.52
    UI.Theme.setColor(node.unlocked and UI.Theme.colors.text or UI.Theme.colors.textDim,
        node.unlocked and 1 or (entry.available and 0.85 or 0.5))
    UI.Glyph.draw(icon, entry.x + (entry.w - size) / 2, entry.y + (entry.h - size) / 2, size)
end

function Achievements:drawTree()
    local view = self.treePane
    local c, m = UI.Theme.colors, UI.Theme.metrics

    love.graphics.setColor(c.panel)
    love.graphics.rectangle("fill", view.x, view.y, view.w, view.h, m.radius, m.radius, 8)
    -- The border picks up the focus glow, so the keyboard being "inside" the
    -- tree reads the same way focus reads on any other control.
    love.graphics.setColor(UI.Theme.lerp(c.panelBorder, c.accent, view.glow))
    love.graphics.rectangle("line", view.x, view.y, view.w, view.h, m.radius, m.radius, 8)

    -- Clipped to the panel so a panned tree stops at its edge instead of sliding
    -- out over the rest of the screen.
    love.graphics.setScissor(math.floor(view.x), math.floor(view.y),
        math.ceil(view.w), math.ceil(view.h))

    local entries = self:activeCategory().entries

    -- Connectors first, so every line runs behind the tiles it joins. A link
    -- into an earned node is lit; the rest are structural.
    for _, entry in ipairs(entries) do
        if entry.parent then
            local lit = entry.node.unlocked
            UI.Theme.setColor(lit and c.accent or c.panelBorder, lit and 0.9 or 0.5)
            drawConnector(entry.parent, entry)
        end
    end

    for _, entry in ipairs(entries) do
        self:drawNode(entry)
    end

    love.graphics.setScissor()
    love.graphics.setColor(1, 1, 1, 1)
end

-- Status word and the color it's said in — the first thing to read in the panel,
-- because everything under it means something different depending on it.
function Achievements:selectedStatus()
    local entry = self.selected
    local c = UI.Theme.colors
    if entry.node.unlocked then return I18n.t("achievements.status.earned"), c.accent end
    if entry.available then
        availableFrame[1], availableFrame[2], availableFrame[3] =
            UI.Theme.lerp(c.panelBorder, c.accent, 0.8)
        return I18n.t("achievements.status.available"), availableFrame
    end
    return I18n.t("achievements.status.locked"), c.textDim
end

function Achievements:drawDetail()
    local panel = self.detail
    local entry = self.selected
    if not entry then return end

    local node = entry.node
    local hidden = isHidden(node)
    local c = UI.Theme.colors
    local pad = UI.Theme.px(DETAIL_PAD)
    local innerX, innerW = panel.x + pad, panel.w - pad * 2

    UI.Theme.panel(panel.x, panel.y, panel.w, panel.h)

    -- Icon, big, in the state's own color: the panel and the tile it describes
    -- read as the same object.
    local frame = nodeColors(entry)
    local iconSize = UI.Theme.px(DETAIL_ICON)
    UI.Theme.setColor(frame)
    UI.Glyph.draw(hidden and "lock" or node.icon,
        innerX + (innerW - iconSize) / 2, panel.y + pad, iconSize)

    local y = panel.y + pad + iconSize + UI.Theme.px(14)

    local titleFont = UI.Theme.font("button")
    UI.Label.draw{
        text = hidden and I18n.t("achievements.hiddenTitle") or nodeText(node.title),
        x = innerX, y = y, width = innerW, font = titleFont,
        color = node.unlocked and c.text or c.textMuted,
    }
    y = y + titleFont:getHeight() + UI.Theme.px(4)

    local smallFont = UI.Theme.font("small")
    local statusText, statusColor = self:selectedStatus()
    UI.Label.draw{
        text = statusText, x = innerX, y = y, width = innerW,
        font = smallFont, color = statusColor,
    }
    y = y + smallFont:getHeight() + UI.Theme.px(16)

    -- Description, wrapped. Label measures through UI.Text's cache, so asking
    -- for the wrap here costs a table lookup rather than a re-layout.
    local bodyFont = UI.Theme.font("small")
    local descText = hidden and I18n.t("achievements.hiddenDesc") or nodeText(node.desc)
    local _, lines = bodyFont:getWrap(descText, innerW)
    UI.Label.draw{
        text = descText, x = innerX, y = y, width = innerW,
        font = bodyFont, color = c.textMuted,
    }
    y = y + math.max(1, #lines) * bodyFont:getHeight() + UI.Theme.px(16)

    -- Reward: the payload. Divider above it so it reads as a separate claim from
    -- the description rather than another sentence of it.
    UI.Theme.setColor(c.panelBorder, 0.8)
    love.graphics.line(innerX, y, innerX + innerW, y)
    y = y + UI.Theme.px(12)

    UI.Label.draw{
        text = I18n.t("achievements.reward"), x = innerX, y = y, width = innerW,
        font = smallFont, color = c.textDim,
    }
    y = y + smallFont:getHeight() + UI.Theme.px(2)

    UI.Label.draw{
        text = hidden and I18n.t("achievements.hiddenReward") or nodeText(node.reward),
        x = innerX, y = y, width = innerW,
        font = smallFont,
        color = node.unlocked and c.accent or c.textMuted,
    }

    -- Pinned to the foot of the panel rather than following the text: how far
    -- along *this* branch is, which is what decides whether to keep working it
    -- or switch tabs. The bar under the screen counts the whole game.
    local category = self:activeCategory()
    UI.Label.draw{
        text = I18n.t("achievements.categoryProgress", {
            name = I18n.t("achievements.category." .. category.id),
            done = category.earned,
            total = #category.entries,
        }),
        x = innerX,
        y = panel.y + panel.h - pad - smallFont:getHeight(),
        width = innerW,
        font = smallFont,
        color = c.textDim,
    }
end

-- Draw only. Every rect here was computed by Achievements:layout().
function Achievements:draw()
    local h = love.graphics.getHeight()

    UI.Label.draw{
        text = I18n.t("achievements.title"),
        y = h * HEADING_Y_RATIO,
        font = UI.Theme.font("heading"),
    }

    self.tabBar:draw()
    self.treePane:draw()
    self:drawDetail()

    -- Completion across the whole game, counted out above the bar that shows it.
    local bar = self.barRect
    UI.Label.draw{
        text = self.progressText,
        x = bar.x, y = self.captionY, width = bar.w,
        font = UI.Theme.font("small"),
        color = UI.Theme.colors.textDim,
    }
    self.bar:draw(bar.x, bar.y, bar.w, bar.h)

    self.backButton:draw()
    UI.Label.hint(I18n.t("achievements.hint"))

    -- Asked every frame the cursor is over something that responds (see
    -- UI.Cursor for why this can't live in mousemoved).
    if self.mouseX and self.group:hovering(self.mouseX, self.mouseY) then
        UI.Cursor.want("hand")
    end
end

return Achievements
