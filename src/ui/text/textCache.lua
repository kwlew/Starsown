--- Rasterized text meshes, cached by content and layout, so a label drawn
-- every frame is laid out once. The whole cache is dropped at MAX_ENTRIES
-- rather than evicted one at a time: screens draw a small, stable set of
-- labels, so this only trips on churn.

local TextCache = {}

local MAX_ENTRIES = 64

local cache = {}
local count = 0

function TextCache.clear()
    cache = {}
    count = 0
end

---@param str string
---@param font any # a love.Font
---@param width number # wrap width
---@param align "left"|"center"|"right"|"justify"
---@return any # a love.Text
function TextCache.get(str, font, width, align)
    local key = table.concat({ str, tostring(font), tostring(width), align }, "\1")
    local entry = cache[key]
    if entry then return entry end

    if count >= MAX_ENTRIES then TextCache.clear() end

    entry = love.graphics.newText(font)
    entry:setf(str, width, align)
    cache[key] = entry
    count = count + 1
    return entry
end

return TextCache
