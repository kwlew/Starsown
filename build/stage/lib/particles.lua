-- lib/particles.lua
-- Namespace for the background effects:
--
--   local Particles = require "lib.particles"
--   Particles.Stars.new{ ... }
--
-- (A .lua file rather than lib/particles/init.lua because these modules resolve
-- through plain package.path, which may not include ?/init.lua.)

return {
    Stars = require "lib.particles.stars",
    Starfield = require "lib.particles.starfield",
    Nebula = require "lib.particles.nebula",
    Burst = require "lib.particles.burst",
}
