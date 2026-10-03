--- Turns one worker result into an outcome. Pure.

local Json = require("lib.json")

local Reply = {}

local SNIPPET = 160

---@param body any
---@return string
local function snippet(body)
    if type(body) ~= "string" or body == "" then return "empty body" end
    return body:sub(1, SNIPPET)
end

--- only a 4xx other than 429 won't change on retry
---@param code integer
---@return boolean
local function retryable(code)
    return code < 400 or code >= 500 or code == 429
end

---@param value any
---@return integer|nil
local function count(value)
    return type(value) == "number" and math.floor(value) or nil
end

--- { fatal?, error?, retry?, totals? } describing what happened
---@param result table
---@return table
function Reply.read(result)
    if result.fatal then return { fatal = result.fatal, detail = result.detail } end
    if result.failure then return { error = "ST-NET", detail = result.failure, retry = true } end
    if result.code ~= 200 then
        return { error = "ST-HTTP-" .. tostring(result.code), detail = snippet(result.body),
            retry = retryable(result.code) }
    end

    local ok, data = pcall(Json.decode, result.body or "")
    if not ok or type(data) ~= "table" then
        return { error = "ST-BADREPLY", detail = snippet(result.body) }
    end
    return { totals = {
        online = count(data.online),
        stars = count(data.stars),
        golden = count(data.golden),
        rainbow = count(data.rainbow),
    } }
end

return Reply
