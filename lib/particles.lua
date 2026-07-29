-- lib/particles.lua
-- Namespace for the game's UI toolkit. Usage:
--
--   local Particles = require "lib.particles"
--   Particles.Stars.new{ ... }
--
-- (This lives at lib/particles.lua rather than lib/ui/init.lua because these modules
-- resolve through plain package.path, which may not include ?/init.lua.)

return {
    Stars = require "lib.particles.stars",
    Starfield = require "lib.particles.starfield",
    Nebula = require "lib.particles.nebula",
    Burst = require "lib.particles.burst",
}
