-- src/states/options.lua
-- Settings screen. Each item toggles/cycles a value in the shared settings
-- table (created during loading) and applies it immediately. Esc or "Back"
-- returns to the main menu.

local StateManager = require "lib.stateManager"
local Menu = require "lib.menu"
local Assets = require "lib.assets"

local Options = {}

local function onOff(value)
    return value and "ON" or "OFF"
end

function Options:enter()
    self.settings = Assets.get("settings") or { fullscreen = false, vsync = 0, volume = 0.8 }
    self.headingFont = Assets.get("headingFont")

    self.menu = self.menu or Menu.new({
        {
            label = function() return "Fullscreen: " .. onOff(self.settings.fullscreen) end,
            onSelect = function()
                self.settings.fullscreen = not self.settings.fullscreen
                love.window.setFullscreen(self.settings.fullscreen)
            end,
        },
        {
            label = function() return "VSync: " .. onOff(self.settings.vsync == 1) end,
            onSelect = function()
                self.settings.vsync = (self.settings.vsync == 1) and 0 or 1
                love.window.setVSync(self.settings.vsync)
            end,
        },
        {
            label = function() return "Volume: " .. math.floor(self.settings.volume * 100 + 0.5) .. "%" end,
            onSelect = function()
                -- Cycle in 20% steps; wraps back to 0 after 100%.
                self.settings.volume = self.settings.volume >= 1 and 0 or self.settings.volume + 0.2
                love.audio.setVolume(self.settings.volume)
            end,
        },
        {
            label = "Back",
            onSelect = function()
                StateManager.switch("mainMenu")
            end,
        },
    }, Assets.get("menuFont"))
end

function Options:keypressed(key)
    if key == "escape" then
        StateManager.switch("mainMenu")
        return
    end
    self.menu:keypressed(key)
end

function Options:draw()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()

    local previousFont = love.graphics.getFont()
    if self.headingFont then love.graphics.setFont(self.headingFont) end
    love.graphics.printf("OPTIONS", 0, 120, w, "center")
    love.graphics.setFont(previousFont)

    self.menu:draw(280, 46)

    love.graphics.printf("Enter: change    Esc / Back: menu", 0, h - 60, w, "center")
end

return Options
