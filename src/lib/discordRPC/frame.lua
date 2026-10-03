local Frame = {}

function Frame.packU32LE(n)
    return string.char(
        n                           % 256,
        math.floor(n / 256)         % 256,
        math.floor(n / 65536)       % 256,
        math.floor(n / 16777216)    % 256
    )
end

function Frame.unpackU32LE(s, offset)
    local b1, b2, b3, b4 = s:byte(offset, offset + 3)
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

return Frame