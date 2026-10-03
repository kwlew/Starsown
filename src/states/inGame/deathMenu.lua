--- The death panel: low, see-through, after the death plays.

local I18n = require("core.i18n")
local Overlay = require("states.inGame.overlay")

local DeathMenu = {}
DeathMenu.__index = DeathMenu

local PANEL_DELAY = 0.7  -- s before the panel appears
local INPUT_DELAY = 0.25 -- s more, so a held attack can't respawn

---@param actions table # { respawn, quit }
---@return table
function DeathMenu.new(actions)
    -- no confirmation: dying already ended the run's stakes
    return setmetatable({
        dead = false,
        deadFor = 0,
        overlay = Overlay.new{
            title = "game.death.title",
            hint = "game.death.hint",
            divider = "danger",
            anchor = 0.72,
            scrim = 0.3,
            panelAlpha = 0.55,
            items = {
                { label = function() return I18n.t("game.death.respawn") end, icon = "play", primary = true,
                  onSelect = actions.respawn },
                { label = function() return I18n.t("game.pause.quit") end, icon = "quit", danger = true,
                  onSelect = actions.quit },
            },
        },
    }, DeathMenu)
end

---@param dead boolean
function DeathMenu:setDead(dead)
    self.dead, self.deadFor = dead, 0
    if not dead then self.overlay:setOpen(false) end
end

---@return table|nil # the menu, once it takes input
function DeathMenu:input()
    if self.dead and self.deadFor >= PANEL_DELAY + INPUT_DELAY then return self.overlay.menu end
end

function DeathMenu:layout()
    self.overlay:layout()
end

---@param dt number
function DeathMenu:update(dt)
    if self.dead then
        self.deadFor = self.deadFor + dt
        if not self.overlay.open and self.deadFor >= PANEL_DELAY then self.overlay:setOpen(true) end
    end
    self.overlay:update(dt)
end

function DeathMenu:draw()
    self.overlay:draw()
end

return DeathMenu
