--- Reusable steering for `think`. Each sets move and speed.
-- goalX/goalY and `state` are kept for the debug view.

local Math = require("utils.math")

local Behaviors = {}

local IDLE_CHANCE = 0.4
local WANDER_SPEED = 0.35 -- of maxSpeed

--- stroll somewhere random, pause, pick again
---@param e table
---@param dt number
---@param speedScale? number
function Behaviors.wander(e, dt, speedScale)
    e.wanderTimer = (e.wanderTimer or 0) - dt
    if e.wanderTimer <= 0 then
        if math.random() < IDLE_CHANCE then
            e.wanderX, e.wanderY, e.wanderTimer = 0, 0, Math.randRange(1, 3)
        else
            local a = Math.randAngle()
            e.wanderX, e.wanderY, e.wanderTimer = math.cos(a), math.sin(a), Math.randRange(1.5, 4)
        end
    end
    e:setMove(e.wanderX, e.wanderY)
    e.goalX, e.goalY = nil, nil
    e.state = (e.wanderX == 0 and e.wanderY == 0) and "idle" or "wander"
    e.speed = e.maxSpeed * (speedScale or WANDER_SPEED)
end

--- head for `target`, stopping once touching
---@param e table
---@param target table
function Behaviors.chase(e, target)
    local dx, dy = target.x - e.x, target.y - e.y
    if Math.length(dx, dy) <= e.radius + target.radius then
        e:setMove(0, 0)
    else
        e:setMove(dx, dy)
    end
    e.goalX, e.goalY, e.state, e.speed = target.x, target.y, "chase", e.maxSpeed
end

---@param e table
---@param threat table
function Behaviors.flee(e, threat)
    e:setMove(e.x - threat.x, e.y - threat.y)
    e.goalX, e.goalY, e.state, e.speed = nil, nil, "flee", e.maxSpeed
end

return Behaviors
