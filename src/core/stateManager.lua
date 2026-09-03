local Theme = require "ui.core.theme"

local StateManager = {
    states = {},
    current = nil,
    currentName = nil,
}

local FADE_HALF = 0.14
local fade = nil

--- a state is a plain table with optional enter/update/draw and LÖVE input
-- callbacks -- every method optional, plus chordpressed(key) for F3 chords
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

--- what "back" means for a screen reachable from more than one place: an
-- explicit opts.returnTo wins, else wherever the player came from, and never
-- the screen itself
---@param previousName string|nil
---@param opts table|nil # the table passed to enter; only opts.returnTo is read
---@param selfName string # the calling screen, so it can't return to itself
---@param fallback? string # defaults to "mainMenu"
---@return string
function StateManager.returnTarget(previousName, opts, selfName, fallback)
    local target = (type(opts) == "table" and opts.returnTo) or previousName
    if not target or target == selfName then
        target = fallback or "mainMenu"
    end
    return target
end

--- swaps states immediately, cancelling any fade in flight. There is no
-- leave() hook by design -- cleanup is destination-dependent, so the arriving
-- state gets the previous name and decides.
---@param name string
---@param ... any # forwarded to the new state's enter(previousName, ...)
function StateManager.switch(name, ...)
    local nextState = StateManager.states[name]
    assert(nextState, "StateManager.switch: no state registered named '" .. tostring(name) .. "'")

    fade = nil

    local previousName = StateManager.currentName
    StateManager.current = nextState
    StateManager.currentName = name

    if nextState.enter then
        nextState:enter(previousName, ...)
    end
end

--- switches through the theme background colour instead of instantly. A
-- second call while a fade is running is ignored, so a double click can't
-- queue two transitions.
---@param name string
---@param ... any # forwarded to enter() when the switch lands
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

---@return boolean
function StateManager.isTransitioning()
    return fade ~= nil
end

---@return number # 0..1 opacity of the fade cover this frame
local function fadeAlpha()
    if not fade then return 0 end
    local k = math.min(1, fade.t / FADE_HALF)
    return fade.phase == "out" and k or (1 - k)
end

--- advances the fade (switching states at its midpoint) and the current state
---@param dt number
function StateManager.update(dt)
    if fade then
        fade.t = fade.t + dt
        if fade.t >= FADE_HALF then
            if fade.phase == "out" then
                local pending = fade
                StateManager.switch(pending.name, unpack(pending.args, 1, pending.args.n))
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

--- the current state, then the fade cover over it
function StateManager.draw()
    local state = StateManager.current
    if state and state.draw then
        state:draw()
    end

    local alpha = fadeAlpha()
    if alpha > 0 then
        Theme.setColor(Theme.colors.bg, alpha)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())
        love.graphics.setColor(1, 1, 1, 1)
    end
end

local blockedWhileFading = {
    keypressed = true, chordpressed = true, textinput = true,
    mousepressed = true, mousereleased = true, wheelmoved = true,
}

local callbacks = {
    "keypressed", "keyreleased", "chordpressed", "textinput",
    "mousepressed", "mousereleased", "mousemoved", "wheelmoved",
    "resize",
}

--- forwards each LÖVE input/resize callback to the current state's own, if it
-- has one. Input is dropped mid-fade -- everything except mouse-move and
-- resize, which would otherwise leave stale hover/layout on arrival.
for _, name in ipairs(callbacks) do
    ---@diagnostic disable-next-line: assign-type-mismatch
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
