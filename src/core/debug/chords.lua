--- F3: tap toggles the overlay, hold+key is a chord.

local Overlay = require("core.debug.overlay")

local Chords = {}

local KEY = "f3"
local chorded = false

---@param key string
---@param isrepeat boolean
---@return boolean consumed
---@return string|nil chord # a key pressed while F3 is held
function Chords.keypressed(key, isrepeat)
    if key == KEY then
        if not isrepeat then chorded = false end
        return true
    end
    if love.keyboard.isDown(KEY) then
        chorded = true
        return true, key
    end
    return false
end

--- toggles on release, unless the hold was a chord
---@param key string
---@return boolean consumed
function Chords.keyreleased(key)
    if key ~= KEY then return false end
    if not chorded then Overlay.toggle() end
    return true
end

return Chords
