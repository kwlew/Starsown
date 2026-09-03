local Text = {}
local MAX_ENTRIES = 64

local cache = {}
local count = 0

--- drops every cached mesh; call when the font scale changes underneath them
function Text.clear()
    cache = {}
    count = 0
end

--- the rasterized mesh for one label, cached by its content and layout. The
-- whole cache is dropped at MAX_ENTRIES rather than evicted one at a time --
-- screens draw a small, stable set of labels, so this only trips on churn.
---@param str string
---@param font any # a love.Font
---@param width number # wrap width
---@param align "left"|"center"|"right"|"justify"
---@return any # a love.Text
function Text.get(str, font, width, align)
    local key = string.format("%s\1%s\1%d\1%s", str, tostring(font), width, align)
    local entry = cache[key]
    if entry then return entry end

    if count >= MAX_ENTRIES then Text.clear() end

    entry = love.graphics.newText(font)
    entry:setf(str, width, align)
    cache[key] = entry
    count = count + 1
    return entry
end

return Text
