--- Which displays and resolutions the Graphics tab offers.

local Limits = require("core.display.limits")

local Resolutions = {}

local FLOOR = { 1280, 720 } -- if every query fails

local WINDOWED = {
    { 800, 600 }, { 1024, 768 }, { 1152, 864 }, { 1280, 720 }, { 1280, 800 },
    { 1280, 960 }, { 1280, 1024 }, { 1360, 768 }, { 1366, 768 }, { 1440, 900 },
    { 1536, 864 }, { 1600, 900 }, { 1600, 1200 }, { 1680, 1050 }, { 1920, 1080 },
    { 1920, 1200 }, { 2560, 1080 }, { 2560, 1440 }, { 2560, 1600 }, { 3440, 1440 },
    { 3840, 2160 },
}

---@return integer[] # 1..display count
function Resolutions.displays()
    local list = {}
    for i = 1, love.window.getDisplayCount() do list[i] = i end
    return list
end

---@param a number[]
---@param b number[]
---@return boolean
local function smaller(a, b)
    if a[1] ~= b[1] then return a[1] < b[1] end
    return a[2] < b[2]
end

--- de-duplicated, at least the minimum size, smallest first
---@param sizes number[][]
---@param display integer
---@param maxW? number
---@param maxH? number
---@return number[][]
local function filtered(sizes, display, maxW, maxH)
    local minW, minH = Limits.minimum(display)
    local seen, list = {}, {}
    for _, size in ipairs(sizes) do
        local w, h = size[1], size[2]
        local key = w .. "x" .. h
        if not seen[key] and w >= minW and h >= minH and w <= (maxW or w) and h <= (maxH or h) then
            seen[key] = true
            list[#list + 1] = { w, h }
        end
    end
    table.sort(list, smaller)
    return list
end

--- exactly the modes the display reports
---@param display integer
---@return number[][]
local function exclusive(display)
    local sizes = {}
    for _, mode in ipairs(love.window.getFullscreenModes(display)) do
        sizes[#sizes + 1] = { mode.width, mode.height }
    end
    return filtered(sizes, display)
end

--- common sizes that fit the desktop, plus the desktop itself
---@param display integer
---@return number[][]
local function windowed(display)
    local deskW, deskH = love.window.getDesktopDimensions(display)
    if type(deskW) ~= "number" or deskW <= 0 or deskH <= 0 then return {} end
    local sizes = { { deskW, deskH } }
    for _, size in ipairs(WINDOWED) do sizes[#sizes + 1] = size end
    return filtered(sizes, display, deskW, deskH)
end

---@param display integer
---@param mode string # a window mode
---@return number[][] # never empty
function Resolutions.list(display, mode)
    if mode == "borderless" then
        local w, h = love.window.getDesktopDimensions(display)
        return { { w, h } }
    end
    local list = mode == "exclusive" and exclusive(display) or windowed(display)
    if #list == 0 then list[1] = { FLOOR[1], FLOOR[2] } end
    return list
end

--- inserts keeping the order; returns where it landed
---@param list number[][]
---@param w number
---@param h number
---@return integer
function Resolutions.insert(list, w, h)
    local entry = { w, h }
    for i, existing in ipairs(list) do
        if smaller(entry, existing) then
            table.insert(list, i, entry)
            return i
        end
    end
    list[#list + 1] = entry
    return #list
end

---@param list number[][]
---@param w number
---@param h number
---@return integer|nil
function Resolutions.find(list, w, h)
    for i, size in ipairs(list) do
        if size[1] == w and size[2] == h then return i end
    end
end

return Resolutions
