-- namespace: local Game = require "game"; Game.World.new{}
-- .lua not game/init.lua because package.path here has no ?/init.lua

return {
    World          = require "game.world",
    Camera         = require "game.camera",
    Entity         = require "game.entity",
    Shape          = require "game.shape",
    Perspective    = require "game.perspective",
    Palette        = require "game.palette",
    Player         = require "game.player",
    Swipe          = require "game.swipe",
    Enemies        = require "game.enemies",
    Items          = require "game.items",
    Inventory      = require "game.inventory",
    InventoryPanel = require "game.inventoryPanel",
    PauseMenu      = require "game.pauseMenu",
    DebugOverlay   = require "game.debugOverlay",
}
