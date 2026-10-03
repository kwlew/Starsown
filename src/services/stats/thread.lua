-- Stats worker: blocking HTTPS requests, off the game thread.

local url, clientId, jobName, resultName, extraCpath = ...

local out = love.thread.getChannel(resultName)

if extraCpath then package.cpath = extraCpath .. ";" .. package.cpath end

local loaded, https = pcall(require, "https")
if not loaded then
    out:push{ fatal = "ST-NOHTTPS", detail = tostring(https):match("^[^\n]*") }
    return
end

local jobs = love.thread.getChannel(jobName)
local endpoint = url .. "?id=" .. clientId
local HEADERS = { ["Content-Type"] = "application/json" }

while true do
    local job = jobs:demand()
    if job == "stop" then break end

    local sent, code, body = pcall(https.request, endpoint, {
        method = "POST",
        data = job.body,
        headers = HEADERS,
    })

    local result = { report = job.report }
    if not sent then
        result.failure = tostring(code)
    elseif type(code) ~= "number" or code == 0 then
        -- lua-https reports transport failures as code 0
        local message = type(body) == "string" and body ~= "" and body or "no HTTP status"
        result.failure = ("%s (host unreachable, connection refused or TLS failure: %s)"):format(message, url)
    else
        result.code, result.body = code, body
    end
    out:push(result)
end
