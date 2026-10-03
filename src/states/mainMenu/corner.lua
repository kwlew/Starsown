--- Bottom corners: links left, version and players right.

local App = require("core.app")
local Globals = require("globals")
local I18n = require("core.i18n")
local UI = require("ui")

local Corner = {}
Corner.__index = Corner

local ICON_SIZE = 26
local PAD = 12 -- matches the loading screen's version pose
local GAP = 8

---@return table
function Corner.new()
    return setmetatable({
        links = {
            UI.IconLink.new{ mark = "github", url = Globals.links.github, label = "GitHub" },
            UI.IconLink.new{ mark = "discord", url = Globals.links.discord, label = "Discord" },
        },
        online = nil,
    }, Corner)
end

--- nil hides the players line until the count is known
---@param count integer|nil
function Corner:setOnline(count)
    self.online = count
end

---@return string|nil
function Corner:onlineText()
    return self.online and I18n.t("menu.onlinePlayers", { n = I18n.number(self.online) })
end

function Corner:layout()
    local w, h = love.graphics.getDimensions()
    local pad, size = UI.Theme.px(PAD), UI.Theme.px(ICON_SIZE)
    local x = pad
    for _, link in ipairs(self.links) do
        link:setBounds(x, h - size - pad, size, size)
        x = x + size + pad
    end

    local font = UI.Theme.font("small")
    self.textY = h - pad - font:getHeight()
    self.versionX = w - font:getWidth(App.VERSION) - pad
end

---@param dt number
function Corner:update(dt)
    for _, link in ipairs(self.links) do link:update(dt) end
end

function Corner:draw()
    local font, color = UI.Theme.font("small"), UI.Theme.colors.textDim
    UI.Label.draw{ text = App.VERSION, x = self.versionX, y = self.textY, align = "left",
        width = font:getWidth(App.VERSION), font = font, color = color }

    local online = self:onlineText()
    if online then
        local width = font:getWidth(online)
        UI.Label.draw{ text = online, x = self.versionX - UI.Theme.px(GAP) - width, y = self.textY,
            align = "left", width = width, font = font, color = color }
    end

    for _, link in ipairs(self.links) do link:draw() end
end

return Corner
