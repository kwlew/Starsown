-- src/core/stateManager.lua
-- Finite state machine for screens. A state is a table that may implement any
-- of enter(previousStateName, ...), update(dt), draw(), and any LÖVE input
-- callback (keypressed, mousepressed, resize, ...). Every method is optional.
--
--   StateManager.register("mainMenu", require "states.mainMenu")
--   StateManager.switch("mainMenu")
--   StateManager.fadeTo("options", { returnTo = "mainMenu" })
--
-- There is no leave() hook: cleanup here is destination-dependent (menu -> game
-- stops the music, menu -> options must not), which a leave() can't express
-- because it doesn't know where you're going. The arriving state gets
-- previousName and decides.

local Theme = require "ui.core.theme"

local StateManager = {
    states = {},
    current = nil,
    currentName = nil,
}

-- Fade-through-black transition. A true crossfade would need both states alive
-- and drawn simultaneously; fading through black needs only one at a time and
-- reads the same at this duration, so the manager stays a plain swap.
--
-- Declared above switch() because switch() assigns to it. A local declared
-- further down the file is not in scope inside a function defined above it, so
-- the assignment would silently create a global and do nothing.
local FADE_HALF = 0.14 -- seconds for each of out and in
local fade = nil       -- { phase = "out" | "in", t, name, args }

function StateManager.register(name, state)
    assert(type(name) == "string", "StateManager.register: name must be a string")
    assert(state ~= nil, "StateManager.register: state cannot be nil")
    StateManager.states[name] = state
    return state
end

-- The registered state for a name, or nil. Screens normally reach each other by
-- switching rather than by holding references — this is for the rarer case of a
-- screen that has to *draw* another one, the way the pause menu draws the state
-- it froze underneath itself.
function StateManager.get(name)
    return StateManager.states[name]
end

-- Where a screen should go when the player backs out of it: an explicit
-- opts.returnTo wins, otherwise wherever they came from, and never `selfName` —
-- a screen re-entered from itself would otherwise have no way out. Any screen
-- opened from more than one place resolves its exit this way.
--
--   self.returnTo = StateManager.returnTarget(previousName, opts, "options")
function StateManager.returnTarget(previousName, opts, selfName, fallback)
    local target = (type(opts) == "table" and opts.returnTo) or previousName
    if not target or target == selfName then
        target = fallback or "mainMenu"
    end
    return target
end

-- Extra arguments are forwarded to the new state's enter().
function StateManager.switch(name, ...)
    local nextState = StateManager.states[name]
    assert(nextState, "StateManager.switch: no state registered named '" .. tostring(name) .. "'")

    -- A switch supersedes any transition in flight. Leaving the fade running
    -- would tick it down and switch a second time, to wherever it was headed,
    -- while painting black over the state we just entered.
    fade = nil

    local previousName = StateManager.currentName
    StateManager.current = nextState
    StateManager.currentName = name

    if nextState.enter then
        nextState:enter(previousName, ...)
    end
end

-- Like switch, but fades out, swaps, and fades back in. Loading -> menu
-- deliberately still uses the instant switch: that hand-off has its own scripted
-- outro, and a fade would just wash it out.
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

function StateManager.isTransitioning()
    return fade ~= nil
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
                StateManager.switch(pending.name, unpack(pending.args, 1, pending.args.n))
                -- switch() cleared the fade; only start the fade-in if the state
                -- we just entered didn't start a transition of its own.
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
        -- The theme's background rather than pure black: it's what both screens
        -- are already cleared to, so the fade bottoms out on the incoming
        -- screen's backdrop instead of dipping past it and back.
        Theme.setColor(Theme.colors.bg, alpha)
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
