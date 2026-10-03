--- The pause overlay, and its "leave this run?" confirmation.

local I18n = require("core.i18n")
local Overlay = require("states.inGame.overlay")
local UI = require("ui")

local PauseMenu = {}
PauseMenu.__index = PauseMenu

---@param actions table # { resume, open(name), quit }
---@return table
function PauseMenu.new(actions)
    local self = setmetatable({}, PauseMenu)
    self.overlay = Overlay.new{
        title = "game.pause.title",
        hint = "game.pause.hint",
        items = {
            { label = function() return I18n.t("game.pause.resume") end, icon = "play", primary = true,
              onSelect = actions.resume },
            { label = function() return I18n.t("menu.achievements") end, icon = "trophy",
              onSelect = function() actions.open("achievements") end },
            { label = function() return I18n.t("menu.options") end, icon = "gear",
              onSelect = function() actions.open("options") end },
            { label = function() return I18n.t("game.pause.quit") end, icon = "quit", danger = true,
              onSelect = function()
                  UI.Sfx.select()
                  self.quitDialog:openDialog()
              end },
        },
    }

    -- Cancel first, so a reflexive Enter keeps the run
    self.quitDialog = UI.Dialog.new{
        title = function() return I18n.t("game.pause.confirmQuit.title") end,
        message = function() return I18n.t("game.pause.confirmQuit.message") end,
        buttons = {
            { label = function() return I18n.t("dialog.cancel") end,
              onSelect = function() self.quitDialog:close() end },
            { label = function() return I18n.t("game.pause.quit") end, danger = true,
              onSelect = actions.quit },
        },
    }
    self.quitDialog:onFocusChanged(UI.Sfx.focus)
    return self
end

---@param open boolean
---@param instant? boolean
function PauseMenu:setOpen(open, instant)
    self.quitDialog:close()
    self.overlay:setOpen(open, instant)
end

--- the dialog when it's up, else the menu
---@return table
function PauseMenu:input()
    return self.quitDialog:isOpen() and self.quitDialog or self.overlay.menu
end

function PauseMenu:layout()
    self.overlay:layout()
    self.quitDialog:layout()
end

---@param dt number
function PauseMenu:update(dt)
    self.overlay:update(dt)
    if self.quitDialog:isOpen() then self.quitDialog:update(dt) end
end

function PauseMenu:draw()
    self.overlay:draw()
    if self.quitDialog:isOpen() then self.quitDialog:draw() end
end

return PauseMenu
