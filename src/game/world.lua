--- One run's entities and leftover effects.
-- Removal only marks; the list is swept after each step.

local Separation = require("game.physics.separation")

local World = {}
World.__index = World

---@param w number # design-space bounds
---@param h number
---@return table
function World.new(w, h)
    return setmetatable({ w = w, h = h, entities = {}, effects = {}, camera = nil }, World)
end

---@param entity table
---@return table entity
function World:add(entity)
    entity.world = self
    self.entities[#self.entities + 1] = entity
    return entity
end

---@param Type table # an Entity type
---@param opts? table
---@return table
function World:spawn(Type, x, y, opts)
    return self:add(Type:new(x, y, opts))
end

---@param effect table # update(dt), draw(), done()
function World:addEffect(effect)
    self.effects[#self.effects + 1] = effect
end

--- drops dead entities
function World:sweep()
    local kept = {}
    for _, e in ipairs(self.entities) do
        if e.alive then kept[#kept + 1] = e else e.world = nil end
    end
    self.entities = kept
end

---@param dt number
function World:tick(dt)
    local list = self.entities
    for i = 1, #list do -- spawned mid-tick starts next tick
        if list[i].alive then list[i]:tick(dt, self) end
    end
    Separation.resolve(self.entities, self)
    self:sweep()
end

--- the per-frame hook, between ticks
---@param dt number
---@param alpha number # 0..1 into the next tick
function World:frame(dt, alpha)
    local list = self.entities
    for i = 1, #list do
        if list[i].alive then list[i]:frame(dt, self, alpha) end
    end
    local kept = {}
    for _, effect in ipairs(self.effects) do
        effect:update(dt)
        if not effect:done() then kept[#kept + 1] = effect end
    end
    self.effects = kept
    self:sweep()
end

--- live entities, optionally of one kind
---@param kind? string
---@return fun(): table|nil
function World:each(kind)
    local list, i = self.entities, 0
    return function()
        repeat
            i = i + 1
            local e = list[i]
            if e and e.alive and (not kind or e.kind == kind) then return e end
        until e == nil
    end
end

--- the closest live entity of `kind` within `range`
---@param kind? string
---@param range? number
---@return table|nil
function World:nearest(x, y, kind, range)
    local best, bestD2 = nil, range and range * range or math.huge
    for e in self:each(kind) do
        local dx, dy = e.x - x, e.y - y
        local d2 = dx * dx + dy * dy
        if d2 <= bestD2 then best, bestD2 = e, d2 end
    end
    return best
end

--- removes everything except the listed kinds
---@param keep? table<string, boolean>
function World:clear(keep)
    for _, e in ipairs(self.entities) do
        if not (keep and keep[e.kind]) then e:remove() end
    end
    self:sweep()
end

---@param alpha number
function World:draw(alpha)
    for e in self:each() do e:draw(alpha) end
    for e in self:each() do e:drawEffects(alpha) end -- attacks over neighbours
    for _, effect in ipairs(self.effects) do effect:draw() end
end

return World
