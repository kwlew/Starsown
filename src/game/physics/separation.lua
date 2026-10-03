--- Pushes overlapping solid entities apart; lighter ones move more.

local Separation = {}

---@param a table
---@param b table
---@param world table
local function push(a, b, world)
    local dx, dy = b.x - a.x, b.y - a.y
    local min = a.radius + b.radius
    local d2 = dx * dx + dy * dy
    if d2 >= min * min then return end

    local d = math.sqrt(d2)
    local nx, ny = 1, 0 -- exactly stacked: any direction
    if d > 0 then nx, ny = dx / d, dy / d end
    local overlap = min - d
    local ka = b.mass / (a.mass + b.mass)
    local kb = 1 - ka
    a.x, a.y = a.x - nx * overlap * ka, a.y - ny * overlap * ka
    b.x, b.y = b.x + nx * overlap * kb, b.y + ny * overlap * kb
    a:clamp(world)
    b:clamp(world)
end

--- pairwise; fine at current entity counts
---@param list table[]
---@param world table
function Separation.resolve(list, world)
    for i = 1, #list do
        local a = list[i]
        if a.alive and a.solid then
            for j = i + 1, #list do
                local b = list[j]
                if b.alive and b.solid then push(a, b, world) end
            end
        end
    end
end

return Separation
