--- PageUp/PageDown: scroll a page, focus the row at that edge.

local Paging = {}

local PAGE = 0.8 -- of the visible height

---@param scroll table # the ScrollArea
---@param group table # the FocusGroup
---@param direction -1|1
---@return integer|nil # best widget index
local function edgeRow(scroll, group, direction)
    local edge = direction < 0 and scroll.y or scroll.y + scroll.h
    local best, distance
    for i, widget in ipairs(group.widgets) do
        local row = scroll.offsets[widget]
        local y = row and scroll.y + row.y - scroll.targetY
        if row and widget:isInteractive() and y >= scroll.y and y + widget.h <= scroll.y + scroll.h then
            local d = math.abs((direction < 0 and y or y + widget.h) - edge)
            if not distance or d < distance then best, distance = i, d end
        end
    end
    return best
end

---@param scroll table
---@param group table
---@param direction -1|1
function Paging.page(scroll, group, direction)
    if not scroll.offsets[group:focused()] then return end
    scroll:setScroll(scroll.targetY + direction * scroll.h * PAGE, true)
    local best = edgeRow(scroll, group, direction)
    if best then group:setFocus(best) end
    scroll:reveal(group:focused(), true)
end

return Paging
