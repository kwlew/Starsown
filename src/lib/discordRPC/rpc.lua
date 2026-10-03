local Pipe = require("lib.discordRPC.pipe")
local Connection = require("lib.discordRPC.connection")
local json = require("lib.json")

local RPC = {
    lastError = nil,
}

local clientId = nil
local onError = nil
local conn = nil
local state = "disconnected"
local retryTimer = 0
local handshakeTimer = 0
local nonceCounter = 0

local HANDSHAKE_TIMEOUT = 8
local HANDSHAKE_RETRY_DELAY = 2

local function nextNonce()
    nonceCounter = nonceCounter + 1
    return tostring(os.time()) .. "-" .. nonceCounter
end

function RPC.initialize(discordApplicationId, opts)
    clientId = discordApplicationId
    onError = opts and opts.onError
    state = "disconnected"
    retryTimer = 0
    handshakeTimer = 0
end

local function report(code, detail)
    RPC.lastError = code .. ": " .. tostring(detail)
    if onError then onError(code, tostring(detail)) end
end

local function disconnect(code, detail, retryIn)
    if conn then conn:close() end
    conn = nil
    state = "disconnected"
    retryTimer = retryIn or 5
    if code then report(code, detail) end
end

local function tryConnect()
    local pipe = Pipe.connect()
    if not pipe then return end
    conn = Connection.new(pipe)
    local sent, err = conn:sendFrame(0, json.encode({ v = 1, client_id = clientId }))
    if not sent then return disconnect("DC-IO", "handshake: " .. tostring(err)) end
    state = "handshaking"
    handshakeTimer = 0
end

local function describe(data)
    if type(data) ~= "table" then return "no details" end
    local code, message = data.code, data.message
    if code and message then return tostring(code) .. ": " .. tostring(message) end
    return tostring(message or code or "no details")
end

local function handleFrame(opcode, payload)
    if opcode == 1 then
        local msg = json.decode(payload)
        if msg then
            if msg.evt == "READY" then
                state = "connected"
            elseif msg.evt == "ERROR" then
                report("DC-ERROR", (msg.cmd and (msg.cmd .. " -> ") or "") .. describe(msg.data))
            end
        end
    elseif opcode == 2 then -- Discord closed the connection, usually with a reason (4000 = bad app id)
        local data = json.decode(payload)
        local code = type(data) == "table" and data.code
        disconnect("DC-CLOSED" .. (code and ("-" .. tostring(code)) or ""), describe(data))
    elseif opcode == 3 then -- PING: Discord drops clients that don't answer
        if not conn then return end
        local sent, err = conn:sendFrame(4, payload)
        if not sent then disconnect("DC-IO", "pong: " .. tostring(err)) end
    end
end

function RPC.update(dt)
    dt = dt or 0

    if state == "disconnected" then
        retryTimer = retryTimer - dt
        if retryTimer <= 0 then
            tryConnect()
            retryTimer = 5
        end
    end

    if state == "handshaking" then
        handshakeTimer = handshakeTimer + dt
        if handshakeTimer >= HANDSHAKE_TIMEOUT then
            return disconnect("DC-HANDSHAKE", ("Discord accepted the connection but sent no READY within %ds")
                :format(HANDSHAKE_TIMEOUT), HANDSHAKE_RETRY_DELAY)
        end
    end

    if not conn then return end

    local ok, err = pcall(function()
        local open, why = conn:pump()
        if not open then return disconnect("DC-LOST", why) end
        while conn do
            local opcode, payload = conn:popFrame()
            if not opcode then break end
            handleFrame(opcode, payload)
        end
    end
)

    if not ok then disconnect("DC-INTERNAL", err) end
end

local function sendCommand(payload)
    if state ~= "connected" or not conn then return false end
    local sent, err = conn:sendFrame(1, payload)
    if not sent then disconnect("DC-LOST", err) end
    return sent
end

function RPC.setActivity(activity)
    return sendCommand(json.encode({
        cmd = "SET_ACTIVITY",
        args = {
            pid = Pipe.getCurrentPid(),
            activity = activity,
        },
        nonce = nextNonce(),
    }))
end

function RPC.clearActivity()
    return sendCommand(json.encode({
        cmd = "SET_ACTIVITY",
        args = { pid = Pipe.getCurrentPid() },
        nonce = nextNonce(),
    }))
end

function RPC.state()
    return state
end

function RPC.isReady()
    return state == "connected"
end

function RPC.getLastError()
    return RPC.lastError
end

function RPC.shutdown()
    if conn then
        conn:sendFrame(2, "{}") -- opcode 2 = CLOSE; a failure here doesn't matter, we're leaving
        conn:close()
        conn = nil
    end
    state = "disconnected"
end

return RPC