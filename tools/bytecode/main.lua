-- Bytecode for lua file.
function love.load()
    io.stdout:setvbuf("no")

    local outDir = os.getenv("TDIDLE_COMPILE_OUT")
    local strip = os.getenv("TDIDLE_COMPILE_STRIP") == "1"

    if not outDir then
        print("[compile] TDIDLE_COMPILE_OUT not set")
        love.event.quit(1)
        return
    end

    local compiled, failed = 0, 0
    local prefixLen = ("game/"):len()

    local function walk(dir)
        for _, name in ipairs(love.filesystem.getDirectoryItems(dir)) do
            local full = dir .. "/" .. name
            local info = love.filesystem.getInfo(full)
            if info and info.type == "directory" then
                walk(full)
            elseif name:match("%.lua$") then
                -- pcall'd: love.filesystem.load returns (nil, err) for some
                -- failures but *raises* for a hard syntax error -- either
                -- way, one broken file should be reported and skipped, not
                -- take the rest of the compile pass down with it.
                local chunk, loadErr
                local ok, a, b = pcall(love.filesystem.load, full)
                if ok then
                    chunk, loadErr = a, b
                else
                    loadErr = a
                end
                if not chunk then
                    print("[compile] FAILED to load " .. full .. ": " .. tostring(loadErr))
                    failed = failed + 1
                else
                    -- strip(false) keeps line numbers/local names in tracebacks;
                    -- see the -StripDebug switch in build.ps1
                    local bytecode = string.dump(chunk, strip)
                    local rel = full:sub(prefixLen + 1)
                    local outPath = outDir .. "/" .. rel
                    local f, openErr = io.open(outPath, "wb")
                    if not f then
                        print("[compile] FAILED to open '" .. outPath .. "': " .. tostring(openErr))
                        failed = failed + 1
                    else
                        f:write(bytecode)
                        f:close()
                        compiled = compiled + 1
                    end
                end
            end
        end
    end

    walk("game")

    print(("[compile] %d compiled, %d failed"):format(compiled, failed))
    love.event.quit(failed > 0 and 1 or 0)
end
