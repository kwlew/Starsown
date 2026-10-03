--- Runtime facts: name, build version, session start.

local Globals = require("globals")

local App = {}

App.NAME = Globals.game.name

-- written into the archive by the build scripts
local stamped = love.filesystem.read("version.txt")
App.VERSION = stamped and stamped:match("^%s*(%S+)") or "dev"

App.startedAt = 0

--- stamps the session start and seeds the RNG
function App.init()
    App.startedAt = os.time()
    math.randomseed(App.startedAt)
end

return App
