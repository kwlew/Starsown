-- src/particles.lua
-- Namespace for the background effects:
--
--   local Particles = require "particles"
--   Particles.Stars.new{ ... }
--
-- (A .lua file rather than src/particles/init.lua because these modules resolve
-- through plain package.path, which may not include ?/init.lua.)

return {
    Stars = require "particles.stars",
    Starfield = require "particles.starfield",
    Nebula = require "particles.nebula",
    Burst = require "particles.burst",
}
