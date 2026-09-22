local Perspective = {}

Perspective.STAND = 0.5

local LIFT = 1.0

local SCALE = 0.0512

local SHRINK = 0.192

Perspective.SHADOW_SPREAD = 1.1
Perspective.SHADOW_SQUASH = 0.42
Perspective.SHADOW_ALPHA = 0.5

--- Lift the position of an object based on its z-coordinate.
---@param z number Current player Z position.
---@return number newZ The new Z position.
function Perspective.lift(z)
    return (z or 0) * LIFT
end

--- Scale an object based on its z-coordinate.
---@param z number Current player Z position.
---@return number newScale The new scale.
function Perspective.scale(z)
    return 1 + (z or 0) * SCALE
end

--- Fade the shadow of an entity based on height
---@param z number Current z position
---@return number shadowFade How much the shadow should be faded.
function Perspective.shadowFade(z)
    return 1 / (1 + (z or 0) * SHRINK)
end

return Perspective