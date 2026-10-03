--- Popped stars not yet reported, kept across launches.

local Backlog = {}

local FILE = "stats_pending"
local MAX = 5000

local counts = { stars = 0, golden = 0, rainbow = 0 }
local loaded = false -- never overwrite a file we haven't read

--- golden and rainbow are subsets of stars, capped to fit
---@param stars number
---@param golden number
---@param rainbow number
local function set(stars, golden, rainbow)
    counts.stars = math.min(stars, MAX)
    counts.golden = math.min(golden, counts.stars)
    counts.rainbow = math.min(rainbow, counts.stars - counts.golden)
end

function Backlog.load()
    loaded = true
    local saved = love.filesystem.read(FILE)
    if not saved then return end
    love.filesystem.remove(FILE)

    local stars, golden, rainbow = saved:match("^(%d+)%s+(%d+)%s+(%d+)")
    if not stars then
        stars, golden = saved:match("^(%d+)%s+(%d+)") -- before rainbow stars existed
        rainbow = "0"
    end
    stars, golden, rainbow = tonumber(stars), tonumber(golden), tonumber(rainbow)
    if not stars or not golden or not rainbow or golden + rainbow > stars then return end
    set(stars, golden, rainbow)
end

function Backlog.save()
    if not loaded then return end
    if counts.stars <= 0 then
        love.filesystem.remove(FILE)
        return
    end
    love.filesystem.write(FILE, ("%d %d %d"):format(counts.stars, counts.golden, counts.rainbow))
end

---@param kind? "golden"|"rainbow"
function Backlog.add(kind)
    if counts.stars >= MAX then return end
    counts.stars = counts.stars + 1
    if kind == "golden" then counts.golden = counts.golden + 1 end
    if kind == "rainbow" then counts.rainbow = counts.rainbow + 1 end
end

--- removes up to `max` stars for one report
---@param max integer
---@return table # { stars, golden, rainbow }
function Backlog.take(max)
    local stars = math.min(counts.stars, max)
    local golden = math.min(counts.golden, stars)
    local rainbow = math.min(counts.rainbow, stars - golden)
    set(counts.stars - stars, counts.golden - golden, counts.rainbow - rainbow)
    return { stars = stars, golden = golden, rainbow = rainbow }
end

--- returns an undelivered report
---@param report table
function Backlog.putBack(report)
    set(counts.stars + report.stars, counts.golden + report.golden, counts.rainbow + report.rainbow)
end

function Backlog.clear()
    set(0, 0, 0)
    love.filesystem.remove(FILE)
end

return Backlog
