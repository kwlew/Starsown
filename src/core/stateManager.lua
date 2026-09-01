-- Finite state machine for screens. A state is a table that may implement any
-- of enter(previousStateName, ...), update(dt), draw(), and any LÖVE input
-- callback. Every method is optional.
--
--   StateManager.register("mainMenu", require "states.mainMenu")
--   StateManager.switch("mainMenu")
--   StateManager.fadeTo("options", { returnTo = "mainMenu" })
--
-- No leave() hook: cleanup is destination-dependent (menu->game stops the
-- music, menu->options must not), which leave() can't express since it
-- doesn't know where you're going. The arriving state gets previousName instead.

local Theme = require "ui.core.theme"

local StateManager = {
    states = {},
    current = nil,
    currentName = nil,
}

-- fade-through-black; declared above switch() since switch() assigns to it
-- and a local further down isn't in scope inside a function above it
local FADE_HALF = 0.14 -- seconds for each of out and in
local fade = nil       -- { phase = "out" | "in", t, name, args }

function StateManager.register(name, state)
    assert(type(name) == "string", "StateManager.register: name must be a string")
    assert(state ~= nil, "StateManager.register: state cannot be nil")
    StateManager.states[name] = state
    return state
end

function StateManager.get(name)
    return StateManager.states[name]
end

-- explicit opts.returnTo wins, else wherever the player came from, and never
-- selfName (a screen re-entered from itself would have no way out)
--
--   self.returnTo = StateManager.returnTarget(previousName, opts, "options")
function StateManager.returnTarget(previousName, opts, selfName, fallback)
    local target = (type(opts) == "table" and opts.returnTo) or previousName
    if not target or target == selfName then
        target = fallback or "mainMenu"
    end
    return target
end

function StateManager.switch(name, ...)
    local nextState = StateManager.states[name]
    assert(nextState, "StateManager.switch: no state registered named '" .. tostring(name) .. "'")

    -- a switch supersedes any transition in flight
    fade = nil

    local previousName = StateManager.currentName
    StateManager.current = nextState
    StateManager.currentName = name

    if nextState.enter then
        nextState:enter(previousName, ...)
    end
end

-- loading -> menu deliberately uses the instant switch instead: that hand-off
-- has its own scripted outro and a fade would wash it out
function StateManager.fadeTo(name, ...)
    assert(StateManager.states[name], "StateManager.fadeTo: no state named '" .. tostring(name) .. "'")
    if fade then return end
    fade = {
        phase = "out",
        t = 0,
        name = name,
        args = { n = select("#", ...), ... },
    }
end

function StateManager.isTransitioning()
    return fade ~= nil
end

-- 0 = fully visible, 1 = fully black
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
                StateManager.switch(pending.name, unpack(pending.args, 1, pending.args.n))
                -- only start the fade-in if the entered state didn't start its own transition
                if not fade then fade = { phase = "in", t = 0 } end
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
        -- fade to the theme's bg, not pure black, so it bottoms out on the
        -- incoming screen's own backdrop
        Theme.setColor(Theme.colors.bg, alpha)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())
        love.graphics.setColor(1, 1, 1, 1)
    end
end

-- dropped while transitioning so mashing Esc can't queue a second switch;
-- cursor movement/resize still get through or the far side lands with stale hover/layout.
-- keyreleased is deliberately not blocked: a release can't start a transition, and
-- swallowing it strands the key as held in whatever tracks it (see Player.held)
local blockedWhileFading = {
    keypressed = true, chordpressed = true, textinput = true,
    mousepressed = true, mousereleased = true, wheelmoved = true,
}

local callbacks = {
    "keypressed", "keyreleased", "chordpressed", "textinput",
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
