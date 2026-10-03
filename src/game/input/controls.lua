--- The player's keys and buttons. The only place they appear.

local Controls = {}

local KEYS = {
    left = { "a", "left" },
    right = { "d", "right" },
    up = { "w", "up" },
    down = { "s", "down" },
    sprint = { "lshift", "rshift" },
}
local ATTACK_BUTTON = 1

---@param action string
---@return boolean
local function held(action)
    return love.keyboard.isDown(unpack(KEYS[action]))
end

---@return number x
---@return number y # -1..1 per axis
function Controls.move()
    local x = (held("right") and 1 or 0) - (held("left") and 1 or 0)
    local y = (held("down") and 1 or 0) - (held("up") and 1 or 0)
    return x, y
end

---@return boolean
function Controls.sprinting()
    return held("sprint")
end

---@return boolean # held chains swings
function Controls.attacking()
    return love.mouse.isDown(ATTACK_BUTTON)
end

return Controls
