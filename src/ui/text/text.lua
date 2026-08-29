-- Cache of love.graphics.Text meshes, so text that changes once a minute
-- isn't laid out and rasterized 500 times a second. Same trick TextFactory
-- does for the title, here for the one-off labels every screen prints.
--
--   local text = Text.get("OPTIONS", font, width, "center")
--   love.graphics.draw(text, x, y)
--
-- Keyed by everything that affects the mesh, so a changed string, font,
-- width, or align is a different entry rather than a stale one. A rescale
-- hands out new Font objects, so its entries just miss naturally.

local Text = {}

-- above this many live entries the whole cache drops rather than evicting
-- one at a time -- past this, the text is genuinely dynamic (a counter, a
-- timer) and caching it was never going to pay off
local MAX_ENTRIES = 64

local cache = {}
local count = 0

function Text.clear()
    cache = {}
    count = 0
end

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
