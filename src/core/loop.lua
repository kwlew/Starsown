--- LÖVE's main loop, with the frame sleep made optional.

local FrameLimiter = require("core.frameLimiter")

---@return fun(): integer|nil
return function()
    ---@diagnostic disable-next-line: redundant-parameter
    if love.load then love.load(love.arg.parseGameArguments(arg), arg) end
    if love.timer then love.timer.step() end

    local dt = 0
    return function()
        if love.event then
            love.event.pump()
            for name, a, b, c, d, e, f in love.event.poll() do
                if name == "quit" and (not love.quit or not love.quit()) then
                    return a or 0
                end
                love.handlers[name](a, b, c, d, e, f)
            end
        end

        if love.timer then dt = love.timer.step() end
        if love.update then love.update(dt) end

        if love.graphics and love.graphics.isActive() then
            love.graphics.origin()
            love.graphics.clear(love.graphics.getBackgroundColor())
            if love.draw then love.draw() end
            love.graphics.present()
        end

        if love.timer and not FrameLimiter.uncapped then love.timer.sleep(0.001) end
    end
end
