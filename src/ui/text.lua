-- src/ui/text.lua
-- Cache of love.graphics.Text meshes, so text that changes once a minute isn't
-- laid out and rasterized 500 times a second. TextFactory already does this for
-- the title; this is the same trick for the one-off labels every screen prints.
--
--   local text = Text.get("OPTIONS", font, width, "center")
--   love.graphics.draw(text, x, y)
--
-- Entries are keyed by everything that affects the mesh, so a changed string,
-- font, wrap width, or alignment is a different entry rather than a stale one.
-- A rescale hands out new Font objects, so its entries miss naturally.

local Text = {}

-- Above this many live entries the whole cache is dropped rather than evicted
-- one at a time. Screens hold a handful of labels, so passing this means the
-- text is genuinely dynamic (a counter, a timer) and caching it was never going
-- to pay off — a periodic wipe keeps that case bounded instead of leaking.
local MAX_ENTRIES = 64

local cache = {}
local count = 0

-- Drops every cached mesh, to release GPU memory on demand.
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
