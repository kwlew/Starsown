--- The current screen, switching between screens, and input forwarding.
-- A state is a table of optional callbacks.

local Fade = require("core.state.fade")

local StateManager = {
    states = {},
    current = nil,
    currentName = nil,
}

local fade = nil

---@param name string
---@param state table
---@return table state
function StateManager.register(name, state)
    assert(type(name) == "string", "StateManager.register: name must be a string")
    assert(state ~= nil, "StateManager.register: state cannot be nil")
    StateManager.states[name] = state
    return state
end

---@param name string
---@return table|nil
function StateManager.get(name)
    return StateManager.states[name]
end

--- where "back" goes: opts.returnTo, else the previous state
---@param previousName string|nil
---@param opts table|nil
---@param selfName string
---@param fallback? string
---@return string
function StateManager.returnTarget(previousName, opts, selfName, fallback)
    local target = (type(opts) == "table" and opts.returnTo) or previousName
    if not target or target == selfName then target = fallback or "mainMenu" end
    return target
end

---@param name string
---@param ... any
local function enter(name, ...)
    local nextState = StateManager.states[name]
    assert(nextState, "StateManager.switch: no state named '" .. tostring(name) .. "'")

    local previousName = StateManager.currentName
    StateManager.current, StateManager.currentName = nextState, name
    if nextState.enter then nextState:enter(previousName, ...) end
end

--- swaps immediately, cancelling any fade
---@param name string
---@param ... any
function StateManager.switch(name, ...)
    fade = nil
    enter(name, ...)
end

--- switches behind a fade; ignored while one is running
---@param name string
---@param ... any
function StateManager.fadeTo(name, ...)
    assert(StateManager.states[name], "StateManager.fadeTo: no state named '" .. tostring(name) .. "'")
    if fade then return end
    fade = Fade.new(name, { n = select("#", ...), ... })
end

---@return boolean
function StateManager.isTransitioning()
    return fade ~= nil
end

---@param dt number
function StateManager.update(dt)
    if fade then
        local midpoint, finished = fade:update(dt)
        if midpoint then enter(fade.name, unpack(fade.args, 1, fade.args.n)) end
        if finished then fade = nil end
    end

    local state = StateManager.current
    if state and state.update then state:update(dt) end
end

function StateManager.draw()
    local state = StateManager.current
    if state and state.draw then state:draw() end
    if fade then fade:draw() end
end

-- moves, resizes and focus still pass mid-fade
local blockedWhileFading = {
    keypressed = true, chordpressed = true, textinput = true,
    mousepressed = true, mousereleased = true, wheelmoved = true,
}

local callbacks = {
    "keypressed", "keyreleased", "chordpressed", "textinput",
    "mousepressed", "mousereleased", "mousemoved", "wheelmoved",
    "resize", "focus",
}

for _, name in ipairs(callbacks) do
    ---@diagnostic disable-next-line: assign-type-mismatch
    StateManager[name] = function(...)
        if fade and blockedWhileFading[name] then return end
        local state = StateManager.current
        local handler = state and state[name]
        if handler then return handler(state, ...) end
    end
end

return StateManager
