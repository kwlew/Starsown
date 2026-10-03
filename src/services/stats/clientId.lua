--- This install's anonymous id: a random, saved UUID.

local ClientId = {}

local FILE = "client_id"
local LENGTH = 36

---@param s string
---@return number
local function hashString(s)
    local h = 0
    for i = 1, #s do h = (h * 31 + s:byte(i)) % 2 ^ 31 end
    return h
end

--- differs every launch, even within one second
---@return number
local function seed()
    return (os.time() * 1000003 + math.floor(os.clock() * 1000000) + hashString(tostring({}))) % 2 ^ 31
end

---@return string # random v4 UUID
local function uuid()
    local rng = love.math.newRandomGenerator(seed())
    return (("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"):gsub("[xy]", function(c)
        local v = c == "x" and rng:random(0, 15) or rng:random(8, 11)
        return ("%x"):format(v)
    end))
end

---@return string
function ClientId.get()
    local saved = love.filesystem.read(FILE)
    if saved and #saved >= LENGTH then return saved:sub(1, LENGTH) end
    local id = uuid()
    love.filesystem.write(FILE, id)
    return id
end

function ClientId.forget()
    love.filesystem.remove(FILE)
end

return ClientId
