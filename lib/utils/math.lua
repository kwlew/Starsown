local Math = {}

function Math.randRange(min, max)
    return min + math.random() * (max - min)
end

return Math