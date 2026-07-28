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

-- Fade-through-black transition. A true crossfade would need both states alive
-- and drawn simultaneously; fading through black needs only one at a time and
-- reads the same at this duration, so the manager stays a plain swap.
--
--   StateManager.fadeTo("options", { returnTo = "mainMenu" })
--
-- Loading -> menu deliberately still uses the instant switch: that hand-off has
-- its own scripted outro, and a fade would just wash it out.
local FADE_HALF = 0.14 -- seconds for each of out and in
local fade = nil       -- { phase = "out" | "in", t, name, args }

function StateManager.isTransitioning()
    return fade ~= nil
end

-- Like switch, but fades out, swaps, and fades back in. Extra arguments reach
-- the new state's enter() exactly as with switch.
function StateManager.fadeTo(name, ...)
    assert(StateManager.states[name], "StateManager.fadeTo: no state named '" .. tostring(name) .. "'")
    if fade then return end -- already going somewhere; ignore the second request
    fade = {
        phase = "out",
        t = 0,
        name = name,
        args = { n = select("#", ...), ... },
    }
end

-- 0 = fully visible, 1 = fully black.
local function fadeAlpha()
    if not fade then return 0 end
    local k = math.min(1, fade.t / FADE_HALF)
    return fade.phase == "out" and k or (1 - k)
end

function StateManager.update(dt)
    if fade then
        fade.t = fade.t + dt
        if fade.t >= FADE_HALF then
            if fade.phase == "out" then
                local pending = fade
                fade = nil -- switch() must not see a transition in flight
                StateManager.switch(pending.name, unpack(pending.args, 1, pending.args.n))
                fade = { phase = "in", t = 0 }
            else
                fade = nil
            end
        end
    end

    local state = StateManager.current
    if state and state.update then
        state:update(dt)
    end
end

function StateManager.draw()
    local state = StateManager.current
    if state and state.draw then
        state:draw()
    end

    local alpha = fadeAlpha()
    if alpha > 0 then
        love.graphics.setColor(0, 0, 0, alpha)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())
        love.graphics.setColor(1, 1, 1, 1)
    end
end

-- Input that could trigger another state change is dropped while a transition
-- runs, so mashing Esc can't queue a second switch behind the first. Cursor
-- movement and resize still get through: blocking those would land on the far
-- side with stale hover state and a stale layout.
local blockedWhileFading = {
    keypressed = true, keyreleased = true, textinput = true,
    mousepressed = true, mousereleased = true, wheelmoved = true,
}

-- Forward the remaining LÖVE callbacks to whichever state is active, but only
-- if that state actually implements the callback.
local callbacks = {
    "keypressed", "keyreleased", "textinput",
    "mousepressed", "mousereleased", "mousemoved", "wheelmoved",
    "resize",
}

for _, name in ipairs(callbacks) do
    StateManager[name] = function(...)
        if fade and blockedWhileFading[name] then return end
        local state = StateManager.current
        local handler = state and state[name]
        if handler then
            return handler(state, ...)
        end
    end
end

return StateManager
