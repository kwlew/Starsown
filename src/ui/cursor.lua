-- src/ui/cursor.lua
-- Frame-scoped mouse cursor arbitration.
--
-- Calling love.mouse.setCursor directly from a screen leaks: whatever was set
-- last stays set after that screen goes away, so hovering a link in the menu
-- and then opening Options leaves the hand cursor over every widget there.
--
-- Instead, a screen *asks* for a cursor each frame it wants one, and the last
-- request before commit() wins. A frame where nobody asks resets to the arrow,
-- so a cursor can never outlive the thing that wanted it.
--
--   function State:draw()  if hovering then UI.Cursor.want("hand") end  end
--   -- once per frame, after every state has drawn:
--   UI.Cursor.commit()
--
-- Ask from update/draw, NOT from mousemoved: mousemoved only fires while the
-- mouse is actually moving, so a request made there would be dropped the moment
-- the player holds still over a button.

local Cursor = {}

local cache = {}    -- system cursor name -> Cursor object (or false if absent)
local wanted = nil  -- name requested during this frame
local applied = nil -- name currently set on the OS, to avoid redundant calls

-- love.mouse.getSystemCursor throws on names a platform doesn't provide, so
-- each lookup is guarded once and the failure cached as `false` — an
-- unavailable cursor quietly falls back to the arrow instead of crashing.
local function systemCursor(name)
    if cache[name] == nil then
        local ok, cursor = pcall(love.mouse.getSystemCursor, name)
        if not ok then
            print(("[cursor] system cursor '%s' unavailable"):format(tostring(name)))
        end
        cache[name] = ok and cursor or false
    end
    return cache[name] or nil
end

-- name is a love.mouse system cursor: "hand", "ibeam", "sizewe", ...
function Cursor.want(name)
    wanted = name
end

-- Applies this frame's request and clears it. Call once per frame at the end of
-- love.draw, after every state has had its say.
function Cursor.commit()
    if wanted ~= applied then
        applied = wanted
        local cursor = applied and systemCursor(applied)
        if cursor then
            love.mouse.setCursor(cursor)
        else
            love.mouse.setCursor() -- no argument = back to the system arrow
        end
    end
    wanted = nil
end

return Cursor
