--- Now and then, a meteor shower: a flurry of stars from one direction.

local Math = require("utils.math")
local Motion = require("ui.core.motion")

local Shower = {}
Shower.__index = Shower

local DURATION = 3.5           -- s a shower lasts
local HEADINGS = { 45, 135 }   -- deg: from the upper left, from the upper right
local HEADING_JITTER = 3       -- deg between its stars
local REDUCED_COUNT_SCALE = 0.5

---@param config? table # intervalMin/Max (s between showers), countMin/Max (stars in one)
---@return table
function Shower.new(config)
    config = config or {}
    local self = setmetatable({
        intervalMin = config.intervalMin or 120,
        intervalMax = config.intervalMax or 300,
        countMin = config.countMin or 10,
        countMax = config.countMax or 16,
        left = 0,
        gap = 0,
        heading = 0,
    }, Shower)
    self.timer = Math.randRange(self.intervalMin, self.intervalMax)
    return self
end

---@return boolean
function Shower:active()
    return self.left > 0
end

function Shower:start()
    local count = Math.randInt(self.countMin, self.countMax)
    if Motion.reduced then count = math.max(1, math.floor(count * REDUCED_COUNT_SCALE)) end
    self.left, self.gap = count, 0
    self.spacing = DURATION / count
    self.heading = HEADINGS[Math.randInt(1, #HEADINGS)]
end

--- at most one star per call
---@param dt number
---@return number|nil angle # radians, when a star should spawn now
function Shower:update(dt)
    if self.left <= 0 then
        self.timer = self.timer - dt
        if self.timer > 0 then return nil end
        self.timer = Math.randRange(self.intervalMin, self.intervalMax)
        self:start()
    end

    self.gap = self.gap - dt
    if self.gap > 0 then return nil end
    self.gap = self.spacing * Math.randRange(0.4, 1.6)
    self.left = self.left - 1
    return math.rad(self.heading + Math.randRange(-HEADING_JITTER, HEADING_JITTER))
end

return Shower
