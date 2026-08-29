local ok, https = pcall(require, "https")
if not ok then return end

local url, clientId, jobName, resultName = ...

local jobs = love.thread.getChannel(jobName)
local out  = love.thread.getChannel(resultName)

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

    out:push{
        code = sent and code or nil,
        body = sent and body or nil,
        stars = job.stars,
        golden = job.golden,
        rainbow = job.rainbow,
    }
end
