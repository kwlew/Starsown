local Frame = require("lib.discordRPC.frame")

local Connection = {}
Connection.__index = Connection

function Connection.new(pipe)
    return setmetatable({
        pipe = pipe,
        buffer = "",
    }, Connection)
end

function Connection:pump()
    local chunk, err = self.pipe:readAvailable()
    if not chunk then return false, err end
    self.buffer = self.buffer .. chunk
    return true
end

function Connection:popFrame()
    if #self.buffer < 8 then return nil end
    local opcode = Frame.unpackU32LE(self.buffer, 1)
    local length = Frame.unpackU32LE(self.buffer, 5)
    if #self.buffer < 8 + length then return nil end
    local payload = self.buffer:sub(9, 8 + length)
    self.buffer = self.buffer:sub(9 + length)
    return opcode, payload
end

function Connection:sendFrame(opcode, payloadStr)
    return self.pipe:write(Frame.packU32LE(opcode) .. Frame.packU32LE(#payloadStr) .. payloadStr)
end

function Connection:close()
    pcall(self.pipe.close, self.pipe)
end

return Connection