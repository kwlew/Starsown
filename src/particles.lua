-- namespace: local Particles = require "particles"; Particles.Stars.new{...}
-- .lua not particles/init.lua because package.path here has no ?/init.lua

return {
    Stars = require "particles.stars",
    Starfield = require "particles.starfield",
    Nebula = require "particles.nebula",
    Burst = require "particles.burst",
}
