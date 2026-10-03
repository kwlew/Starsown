--- Which keys mean which UI action. The only place key names appear, so
-- rebinding (or adding a gamepad later) touches nothing else.

local Bindings = {}

---@alias UiAction "next"|"previous"|"up"|"down"|"left"|"right"|"confirm"|"cancel"

local KEYS = {
    up      = { "up", "w" },
    down    = { "down", "s" },
    left    = { "left", "a" },
    right   = { "right", "d" },
    confirm = { "return", "kpenter", "space" },
    cancel  = { "escape" },
}

local actionFor = {}
for action, keys in pairs(KEYS) do
    for _, key in ipairs(keys) do actionFor[key] = action end
end

--- tab is "next", shift+tab "previous"
---@param key string # a love KeyConstant
---@return UiAction|nil
function Bindings.action(key)
    if key == "tab" then
        return love.keyboard.isDown("lshift", "rshift") and "previous" or "next"
    end
    return actionFor[key]
end

return Bindings
