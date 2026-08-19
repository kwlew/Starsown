-- Compiles every .lua file under game/ (a copy of src/, staged by
-- build.ps1) to LuaJIT bytecode, written to $TDIDLE_COMPILE_OUT with the
-- same relative paths. Driven by build.ps1 -Bytecode, not run directly.
--
-- Compiles through THIS runtime (love.filesystem.load + string.dump) rather
-- than shelling out to a standalone `luajit` binary on PATH: the bytecode
-- format isn't guaranteed stable across LuaJIT builds, and a locally
-- installed luajit.exe has no reason to match whatever's embedded in this
-- LÖVE install. Loading and dumping through LÖVE's own runtime means the
-- bytecode it produces is *exactly* what that runtime will later load back.
--
-- game/ is a plain subdirectory of this project, not an external mount --
-- love.filesystem.mount() returned false for every absolute path tried
-- (even "." and this project's own directory) when this was built, so
-- build.ps1 copies the source in as a subfolder instead of mounting it.
--
-- Output directories must already exist -- io.open won't create them, and
-- build.ps1 mirrors the source tree before launching this.

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
