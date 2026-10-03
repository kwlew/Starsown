--- Compiles a shader on first use and keeps it. A shader that fails to
-- compile is reported once and then returns false, so callers can fall
-- back to drawing without it instead of crashing every frame.

---@param name string # for the error message
---@param source string # GLSL
---@return fun(): any # returns the love.Shader, or false
return function(name, source)
    local shader = nil
    return function()
        if shader == nil then
            local ok, result = pcall(love.graphics.newShader, source)
            if not ok then print("[shader] " .. name .. " failed: " .. tostring(result)) end
            shader = ok and result
        end
        return shader
    end
end
