local Globals = {}

-- version.txt is written into the archive by the build scripts (git describe);
-- an unpackaged `love src` run has none
local stamped = love.filesystem.read("version.txt")

Globals.game = {
    name      = "Starsown",
    version   = stamped and stamped:match("^%s*(%S+)") or "dev",
    startedAt = 0,
}

--- stamps the session start and seeds the RNG from it; call once at boot
function Globals.init()
    Globals.game.startedAt = os.time()
    math.randomseed(Globals.game.startedAt)
end

return Globals
