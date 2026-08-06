-- tests/run.lua
-- Zero-dependency test runner for the pure-Lua parts of the game.
--
--   luajit tests/run.lua              -- run everything
--   luajit tests/run.lua settings     -- run suites/tests matching "settings"
--
-- Always run it from the repository root: the specs `require "lib.x"`, exactly
-- like the game does, and that only resolves with the root on package.path.
--
-- LuaJIT rather than `lua`, because that is what LÖVE embeds (5.1 semantics).
-- Plain lua5.1 works too; a modern lua5.4 does not — the game is 5.1 code.
--
-- Adding a spec: drop it in tests/spec/ and add it to SPECS below. The list is
-- explicit on purpose — directory listing is not portable in stock Lua, and a
-- spec that silently stops being discovered is worse than one line of upkeep.

package.path = "./?.lua;./?/init.lua;" .. package.path

local SPECS = {
    "tests.spec.math_spec",
    "tests.spec.json_spec",
    "tests.spec.audio_spec",
    "tests.spec.settings_spec",
    "tests.spec.i18n_spec",
    "tests.spec.locales_spec",
}

--------------------------------------------------------------------------------
-- The DSL. Exposed as globals so specs read like specs and need no preamble.
--------------------------------------------------------------------------------

local root = { name = nil, tests = {}, children = {}, before = {} }
local stack = { root }

function describe(name, fn)
    local node = { name = name, tests = {}, children = {}, before = {} }
    local parent = stack[#stack]
    parent.children[#parent.children + 1] = node
    stack[#stack + 1] = node
    fn()
    stack[#stack] = nil
end

function it(name, fn)
    local node = stack[#stack]
    node.tests[#node.tests + 1] = { name = name, fn = fn }
end

-- Runs before every test in the enclosing describe (and its nested ones).
function beforeEach(fn)
    local node = stack[#stack]
    node.before[#node.before + 1] = fn
end

--------------------------------------------------------------------------------
-- Assertions. Every one raises a plain string, which the runner turns into a
-- failure line; level 2 blames the calling spec line rather than this file.
--------------------------------------------------------------------------------

local function show(value)
    if type(value) == "string" then return string.format("%q", value) end
    return tostring(value)
end

function fail(message)
    error(message, 3)
end

function assertEqual(actual, expected, message)
    if actual ~= expected then
        fail((message and message .. ": " or "") ..
            ("expected %s, got %s"):format(show(expected), show(actual)))
    end
end

function assertNotEqual(actual, unexpected, message)
    if actual == unexpected then
        fail((message and message .. ": " or "") ..
            ("expected anything but %s"):format(show(unexpected)))
    end
end

function assertTrue(value, message)
    if not value then
        fail((message and message .. ": " or "") .. ("expected truthy, got %s"):format(show(value)))
    end
end

function assertFalse(value, message)
    if value then
        fail((message and message .. ": " or "") .. ("expected falsy, got %s"):format(show(value)))
    end
end

function assertNil(value, message)
    if value ~= nil then
        fail((message and message .. ": " or "") .. ("expected nil, got %s"):format(show(value)))
    end
end

-- Floats: comparing them with == is a coin toss once arithmetic is involved.
function assertNear(actual, expected, epsilon, message)
    epsilon = epsilon or 1e-9
    if type(actual) ~= "number" or math.abs(actual - expected) > epsilon then
        fail((message and message .. ": " or "") ..
            ("expected %s +/- %s, got %s"):format(show(expected), show(epsilon), show(actual)))
    end
end

-- Recursive value equality for tables (keys and values both), used wherever a
-- function returns a table the spec wants to pin down whole.
local function deepEqual(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for key, value in pairs(a) do
        if not deepEqual(value, b[key]) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

function assertDeepEqual(actual, expected, message)
    if not deepEqual(actual, expected) then
        fail((message and message .. ": " or "") .. "tables differ")
    end
end

-- `pattern` is matched against the raised message (a Lua pattern, so escape
-- magic characters). Returns the message for further inspection.
function assertError(fn, pattern, message)
    local ok, err = pcall(fn)
    if ok then
        fail((message and message .. ": " or "") .. "expected an error, none was raised")
    end
    err = tostring(err)
    if pattern and not err:find(pattern) then
        fail((message and message .. ": " or "") ..
            ("error %s does not match %s"):format(show(err), show(pattern)))
    end
    return err
end

function assertNoError(fn, message)
    local ok, err = pcall(fn)
    if not ok then
        fail((message and message .. ": " or "") .. ("raised %s"):format(show(err)))
    end
end

--------------------------------------------------------------------------------
-- Loading and running
--------------------------------------------------------------------------------

local filter = ...

for _, spec in ipairs(SPECS) do
    require(spec)
end

local passed, failed, skipped = 0, 0, 0
local failures = {}

local function traceback(err)
    return tostring(err) .. "\n" .. debug.traceback("", 2)
end

local function matches(fullName)
    return not filter or fullName:lower():find(filter:lower(), 1, true) ~= nil
end

local function labelFor(node, prefix)
    if not node.name then return prefix end
    return prefix ~= "" and (prefix .. " " .. node.name) or node.name
end

local function fullNameOf(label, test)
    return label ~= "" and (label .. " :: " .. test.name) or test.name
end

-- Whether anything under this node survives the filter, so a describe whose
-- tests were all filtered out doesn't print a bare heading.
local function subtreeMatches(node, prefix)
    local label = labelFor(node, prefix)
    for _, test in ipairs(node.tests) do
        if matches(fullNameOf(label, test)) then return true end
    end
    for _, child in ipairs(node.children) do
        if subtreeMatches(child, label) then return true end
    end
    return false
end

local function countTests(node)
    local total = #node.tests
    for _, child in ipairs(node.children) do total = total + countTests(child) end
    return total
end

local function runNode(node, prefix, befores, depth)
    local label = labelFor(node, prefix)
    local indent = ("  "):rep(depth)

    if not subtreeMatches(node, prefix) then
        skipped = skipped + countTests(node)
        return
    end

    if node.name then print(("%s%s"):format(("  "):rep(depth - 1), node.name)) end

    -- before hooks are inherited: an outer describe's setup runs for every test
    -- nested below it, outermost first.
    local scoped = {}
    for _, fn in ipairs(befores) do scoped[#scoped + 1] = fn end
    for _, fn in ipairs(node.before) do scoped[#scoped + 1] = fn end

    for _, test in ipairs(node.tests) do
        local fullName = fullNameOf(label, test)
        if not matches(fullName) then
            skipped = skipped + 1
        else
            local ok, err = true, nil
            for _, fn in ipairs(scoped) do
                if ok then ok, err = xpcall(fn, traceback) end
            end
            if ok then ok, err = xpcall(test.fn, traceback) end

            if ok then
                passed = passed + 1
                print(("%sok   %s"):format(indent, test.name))
            else
                failed = failed + 1
                failures[#failures + 1] = { name = fullName, err = err }
                print(("%sFAIL %s"):format(indent, test.name))
            end
        end
    end

    for _, child in ipairs(node.children) do
        runNode(child, label, scoped, depth + 1)
    end
end

local clock = os.clock()
runNode(root, "", {}, 0)
local elapsed = os.clock() - clock

print("")
if failed > 0 then
    print(("%d failure%s:"):format(failed, failed == 1 and "" or "s"))
    for _, failure in ipairs(failures) do
        print(("\n  %s\n    %s"):format(failure.name, (failure.err:gsub("\n", "\n    "))))
    end
    print("")
end

print(("%d passed, %d failed%s (%.2fs)"):format(
    passed, failed, skipped > 0 and (", " .. skipped .. " filtered out") or "", elapsed))

os.exit(failed == 0 and 0 or 1)
