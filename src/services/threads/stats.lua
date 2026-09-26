-- The stats worker: blocks on the job channel and makes each request, so
-- https.request's blocking never touches the game thread. Everything it
-- learns -- including that it can't run at all -- goes back as a result,
-- because an error that stays in this thread is an error nobody sees.

local url, clientId, jobName, resultName, devCpath = ...

local out = love.thread.getChannel(resultName)

-- an unpackaged `love src` run can't load C modules from the game folder,
-- so the main thread points us at the dev copy of lua-https when it exists
if devCpath then package.cpath = devCpath .. ";" .. package.cpath end

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

    local result = { stars = job.stars, golden = job.golden, rainbow = job.rainbow }
    if not sent then
        result.failure = tostring(code) -- pcall's error message
    elseif type(code) ~= "number" or code == 0 then
        -- lua-https reports a transport failure as code 0, sometimes with a message
        local message = type(body) == "string" and body ~= "" and body or "no HTTP status"
        result.failure = ("%s (host unreachable, connection refused or TLS failure: %s)"):format(message, url)
    else
        result.code, result.body = code, body
    end
    out:push(result)
end
