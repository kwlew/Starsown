--- The menu sky (nebula + stars), shared through Assets.

local Assets = require("core.assets")
local Particles = require("particles")

local Backdrop = {}

---@param settings table
---@param alpha? number
---@return table # Particles.Stars
function Backdrop.newStars(settings, alpha)
    local stars = Particles.Stars.new{ alpha = alpha, enabled = settings.showStars }
    stars:spawnStars()
    return Assets.set("stars", stars)
end

---@param settings table
---@param alpha? number
---@return table # Particles.Nebula, unbaked
function Backdrop.newNebula(settings, alpha)
    return Assets.set("nebula", Particles.Nebula.new{ alpha = alpha, enabled = settings.showNebula })
end

--- the shared layers, built if loading never made them
---@param settings table
---@return table stars
---@return table nebula
function Backdrop.get(settings)
    local stars = Assets.get("stars") or Backdrop.newStars(settings)
    local nebula = Assets.get("nebula") or Backdrop.newNebula(settings)
    if nebula.enabled and not nebula:isBaked() then nebula:bake() end
    return stars, nebula
end

--- rebakes after anything that wipes or recolours it
function Backdrop.rebake()
    local nebula = Assets.get("nebula")
    if nebula and nebula:isBaked() then nebula:bake() end
end

---@param value boolean
function Backdrop.showNebula(value)
    local nebula = Assets.get("nebula")
    if not nebula then return end
    if value and not nebula:isBaked() then nebula:bake() end -- skipped at boot if hidden
    nebula.enabled = value
end

---@param value boolean
function Backdrop.showStars(value)
    local stars = Assets.get("stars")
    if stars then stars.enabled = value end
end

return Backdrop
