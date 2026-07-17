-- lib/stateManager.lua
-- Lightweight finite state machine for LÖVE screens/scenes (menu, options,
-- gameplay, ...). A "state" is just a table that may implement any of:
--
--   state:enter(previousStateName, ...)  -- becomes the active state
--   state:leave()                        -- is replaced by another state
--   state:update(dt)
--   state:draw()
--   ...plus any LÖVE input callback it cares about (keypressed, mousepressed…)
--
-- Every method is optional. Register states once, then call
-- StateManager.switch(name) to change screens.
--
--   StateManager.register("mainMenu", require "states.mainMenu")
--   StateManager.switch("mainMenu")

local StateManager = {
    states = {},       -- name -> state table
    current = nil,     -- active state table
    currentName = nil, -- active state name
}

function StateManager.register(name, state)
    assert(type(name) == "string", "StateManager.register: name must be a string")
    assert(state ~= nil, "StateManager.register: state cannot be nil")
    StateManager.states[name] = state
    return state
end

-- Switches to a registered state. Extra arguments are forwarded to the new
-- state's enter(), so callers can pass data between screens.
function StateManager.switch(name, ...)
    local nextState = StateManager.states[name]
    assert(nextState, "StateManager.switch: no state registered named '" .. tostring(name) .. "'")

    local current = StateManager.current
    if current and current.leave then
        current:leave()
    end

    local previousName = StateManager.currentName
    StateManager.current = nextState
    StateManager.currentName = name

    if nextState.enter then
        nextState:enter(previousName, ...)
    end
end

-- Forward the common LÖVE callbacks to whichever state is active, but only if
-- that state actually implements the callback. This lets main.lua wire
-- love.update / love.draw / love.keypressed / ... straight to StateManager.
local callbacks = {
    "update", "draw",
    "keypressed", "keyreleased", "textinput",
    "mousepressed", "mousereleased", "mousemoved", "wheelmoved",
    "resize",
}

for _, name in ipairs(callbacks) do
    StateManager[name] = function(...)
        local state = StateManager.current
        local handler = state and state[name]
        if handler then
            return handler(state, ...)
        end
    end
end

return StateManager
