-- tests/helpers/love_stub.lua
-- Just enough of the `love` global for the modules that touch it to run outside
-- the engine. Only what the specs actually exercise is implemented; anything
-- else is deliberately absent so a spec that starts depending on a new part of
-- LÖVE fails loudly here instead of quietly testing a lie.
--
--   local Love = require "tests.helpers.love_stub"
--   Love.install{ ["settings.lua"] = "return { volume = 0.5 }" }
--
-- love.filesystem is an in-memory table of path -> contents, seeded per test.
-- It behaves like the real thing on the points the game depends on: read()
-- returns nil for a missing file, load() compiles a chunk (and returns nil for
-- a syntax error), and getInfo() only answers for files that exist.

local Love = {}

-- Set by install(); the spec may read or mutate it mid-test.
Love.files = {}

local function fileNames()
    local names = {}
    for path in pairs(Love.files) do names[#names + 1] = path end
    table.sort(names)
    return names
end

-- Installs a fresh `love` global (and returns it). `files` is an optional
-- path -> contents map for the virtual filesystem.
function Love.install(files)
    Love.files = files or {}
    Love.volume = 1
    Love.identity = nil
    Love.cursorVisible = true
    -- Window state the graphics code reads back; setMode overwrites it.
    Love.mode = {
        width = 1280,
        height = 720,
        flags = {
            fullscreen = false,
            fullscreentype = "desktop",
            vsync = 0,
            msaa = 4,
            resizable = false,
            highdpi = true,
            x = 100,
            y = 100,
        },
    }
    Love.setModeCalls = 0

    local love = {}

    love.filesystem = {
        read = function(path)
            local contents = Love.files[path]
            if not contents then return nil, "Could not open file " .. tostring(path) end
            return contents, #contents
        end,

        write = function(path, contents)
            Love.files[path] = contents
            return true
        end,

        remove = function(path)
            Love.files[path] = nil
            return true
        end,

        getInfo = function(path)
            local contents = Love.files[path]
            if not contents then return nil end
            return { type = "file", size = #contents, modtime = 0 }
        end,

        -- Real LÖVE returns the direct children of a directory. Paths here are
        -- flat strings, so a prefix match is the equivalent.
        getDirectoryItems = function(dir)
            local prefix = (dir == "" or dir == nil) and "" or (dir .. "/")
            local items = {}
            for _, path in ipairs(fileNames()) do
                if path:sub(1, #prefix) == prefix then
                    local rest = path:sub(#prefix + 1)
                    if rest ~= "" and not rest:find("/") then
                        items[#items + 1] = rest
                    end
                end
            end
            return items
        end,

        load = function(path)
            local contents = Love.files[path]
            if not contents then return nil, "file not found" end
            return loadstring(contents, "@" .. path)
        end,

        setIdentity = function(name) Love.identity = name end,
        getIdentity = function() return Love.identity end,
    }

    love.audio = {
        setVolume = function(value) Love.volume = value end,
        getVolume = function() return Love.volume end,
    }

    love.window = {
        getMode = function()
            -- A copy, so a caller mutating the flags table (Settings.applyGraphics
            -- does exactly that) cannot reach back into the stub's state.
            local flags = {}
            for key, value in pairs(Love.mode.flags) do flags[key] = value end
            return Love.mode.width, Love.mode.height, flags
        end,

        setMode = function(width, height, flags)
            Love.setModeCalls = Love.setModeCalls + 1
            Love.mode.width, Love.mode.height = width, height
            local copy = {}
            for key, value in pairs(flags or {}) do copy[key] = value end
            Love.mode.flags = copy
            return true
        end,
    }

    love.mouse = {
        setVisible = function(visible) Love.cursorVisible = visible end,
        isVisible = function() return Love.cursorVisible end,
    }

    love.timer = {
        getTime = function() return 0 end,
    }

    _G.love = love
    return love
end

-- Drops the global again so a spec that forgets to install one gets a clear
-- "attempt to index nil" instead of another spec's leftovers.
function Love.uninstall()
    _G.love = nil
    Love.files = {}
end

-- Re-requires a module against the current stub. Modules cache state at load
-- time (I18n's catalogs, Audio's tracked sources), so a spec that needs a clean
-- one has to evict it from package.loaded first.
function Love.reload(name)
    package.loaded[name] = nil
    return require(name)
end

return Love
