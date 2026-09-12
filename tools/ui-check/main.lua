-- Runs against a temporary copy of src with real LÖVE fonts and rendering.
-- External services are disabled. Transactions use a simulated display driver;
-- real monitor/fullscreen behavior still needs an interactive platform check.
package.loaded["services.presence"] = { set = function() end }
package.loaded["services.stats"] = { setEnabled = function() end }

local UI = require "ui"
local Settings = require "core.settings"
local Assets = require "core.assets"
local I18n = require "core.i18n"
local StateManager = require "core.stateManager"
local Options = require "states.options"
local Limits = require "core.displayLimits"
local checks = 0

local function check(ok, message)
    assert(ok, message)
    checks = checks + 1
end

local function near(a, b) return math.abs(a - b) < 0.01 end

local function focus(widget)
    for i, entry in ipairs(Options.group.widgets) do
        if entry == widget then Options.group:setFocus(i, true); Options:revealFocus(); return end
    end
    error("Widget is not in focus order")
end

local function fresh()
    local settings = {}
    for k, v in pairs(Settings.defaults) do settings[k] = v end
    settings.res_x, settings.res_y = love.graphics.getDimensions()
    Assets.set("settings", settings)
    Options:enter("mainMenu")
    return settings
end

local function resize(w, h)
    assert(love.window.setMode(w, h, { resizable = true, vsync = 0, msaa = 0 }))
    UI.Theme.rescale(h)
    Options:resize()
end

local function render(name)
    local canvas = love.graphics.newCanvas(love.graphics.getDimensions())
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(UI.Theme.colors.bg)
    Options:draw()
    love.graphics.setCanvas()
    if name then canvas:newImageData():encode("png", name .. ".png") end
    love.graphics.pop()
    canvas:release()
end

local function layoutChecks()
    for _, size in ipairs({ {800, 600}, {1024, 768}, {1280, 720}, {1920, 1080}, {3440, 1440} }) do
        resize(unpack(size))
        for _, language in ipairs(I18n.available()) do
            I18n.setLanguage(language.code)
            Options:layout()
            local backY, tabY, viewportH
            for tab = 1, 3 do
                Options:selectTab(tab)
                local area = Options.scroll
                local context = size[1] .. "x" .. size[2] .. "/" .. language.code .. "/" .. tab
                if backY then
                    check(near(backY, Options.backButton.y) and near(tabY, Options.tabBar.y)
                        and near(viewportH, area.h), "Unstable fixed regions: " .. context)
                end
                backY, tabY, viewportH = Options.backButton.y, Options.tabBar.y, area.h
                -- Order top to bottom: tab bar, content panel, status, footer, hint.
                check(area.h > 0 and tabY + Options.tabBar.h <= area.y, "Invalid viewport: " .. context)
                check(area.y + area.h <= Options.statusRect.y, "Panel overlaps status: " .. context)
                check(Options.statusRect.y + Options.statusRect.h <= backY, "Status overlaps actions")
                check(backY + Options.backButton.h <= Options.hintRect.y, "Actions overlap hints")
                check(Options.hintRect.y + Options.hintRect.h <= size[2], "Hints exceed window")
                for _, widget in ipairs(area.widgets) do
                    check(widget.h >= UI.Theme.metrics.rowHeight, "Compressed row: " .. context)
                    check(widget.h <= area.h, "Row cannot be revealed: " .. context)
                    local r = widget.rowLayout
                    check(r.stacked or r.labelX + r.labelW <= r.x, "Label/control collision")
                    check(r.y + r.h <= widget.h and r.x + r.w <= widget.w, "Control exceeds row")
                    if widget:isInteractive() then
                        focus(widget)
                        check(widget.y >= area.y - 0.01 and widget.y + widget.h <= area.y + area.h + 0.01,
                            "Focus is clipped: " .. context)
                    end
                end
                -- Traverse the actual keyboard path into and out of the footer.
                focus(Options.tabBar)
                for _ = 1, #Options.group.widgets * 2 do
                    Options:keypressed("tab")
                    Options:update(1) -- keyboard focus scroll has time to settle
                    local widget = Options.group:focused()
                    if area.offsets[widget] then
                        check(widget.y >= area.y - 0.01 and widget.y + widget.h <= area.y + area.h + 0.01,
                            "Tab focused a clipped row: " .. context)
                    end
                end
                Options.scroll:setScroll(0)
                Options.group:setFocus(1, true)
                Options:update(1)
                render(size[1] == 800 and tab == 3 and ("graphics-800-" .. language.code) or nil)
                if size[1] == 800 then
                    for _, dialog in ipairs({ Options.revertDialog, Options.unappliedDialog }) do
                        Options:openDialog(dialog)
                        check(dialog.panel.y >= 0 and dialog.panel.y + dialog.panel.h <= size[2], "Dialog exceeds minimum window")
                        for _, button in ipairs(dialog.buttons) do
                            local _, lines = button:getFont():getWrap(button:labelText(), button.w)
                            check(#lines * button:getFont():getHeight() <= button.h, "Dialog button text exceeds its height")
                        end
                        render()
                        dialog:close()
                    end
                end
            end
        end
    end
    resize(1280, 720)
    I18n.setLanguage("en")
    Options:selectTab(3)
    for _, palette in ipairs(UI.Theme.available()) do
        UI.Theme.setTheme(palette.id)
        for _, reduced in ipairs({ false, true }) do
            UI.Motion.setReduced(reduced)
            focus(Options.msaaSelector)
            Options:update(0.2)
            render(palette.id == "default" and not reduced and "graphics-1280" or nil)
        end
    end
    UI.Theme.setTheme("default")
end

local function inputChecks()
    UI.Motion.setReduced(true) -- immediate-layout/input invariants; easing is checked separately
    resize(800, 600)
    fresh()
    Options:selectTab(3)
    local area = Options.scroll
    check(area.maxScroll > 0, "Graphics should scroll at the minimum size")
    local height = Options.msaaSelector.h
    -- More content must add scrolling, not compress existing controls.
    local rows = Options.tabs[3].widgets
    local originalCount = #rows
    for i = 1, 5 do rows[#rows + 1] = UI.Toggle.new{ label = "Fixture " .. i } end
    Options:layout()
    check(near(height, Options.msaaSelector.h), "Fixture rows compressed controls")
    -- Test the clipped-click guard against a fixture buried well past the
    -- viewport, not the real last row: with per-row notes gone, real content
    -- is short enough that its natural overflow can land close to the footer.
    area:setScroll(0)
    local last = rows[#rows]
    check(last.y + last.h > area.y + area.h, "Fixture expects a clipped last row")
    local value = last.value
    local clippedY = math.max(last.y + 1, area.y + area.h + 1)
    check(not Options.group:allowsPointer(last, last.x + 5, clippedY), "Clipped row accepts pointer")
    Options.group:mousepressed(last.x + 5, clippedY, 1)
    check(last.value == value, "Click outside viewport changed a clipped control")
    for i = #rows, originalCount + 1, -1 do rows[i] = nil end
    Options:layout()

    Options:mousemoved(area.x + 10, area.y + 10)
    local currentFocus = Options.group:focused()
    Options:wheelmoved(0, -2)
    check(area.scrollY > 0 and Options.group:focused() == currentFocus, "Wheel steals focus or fails to scroll")
    local savedScroll = area.scrollY
    Options:selectTab(1)
    Options:selectTab(3)
    check(near(area.scrollY, savedScroll), "Tab switch loses scroll position")
    local bx, by, bw, bh = area:thumbRect()
    Options:mousepressed(bx + bw / 2, by + bh / 2, 1)
    Options:mousemoved(bx, area.y + area.h + 100)
    Options:mousereleased(bx, area.y + area.h + 100, 1)
    check(near(area.scrollY, area.maxScroll) and not area.dragOffset, "Scrollbar drag failed")

    focus(Options.displaySelector)
    Options:keypressed("pagedown")
    check(area.scrollY > 0, "Page Down did not move content")
    local prior = Options.group.index
    local isDown = love.keyboard.isDown
    love.keyboard.isDown = function() return true end
    Options:keypressed("tab")
    love.keyboard.isDown = isDown
    check(Options.group.index ~= prior, "Shift+Tab did not move focus")

    Options:selectTab(1)
    local slider = Options.musicVolumeSlider
    focus(slider)
    local tx, ty, tw = slider:trackRect()
    Options:mousepressed(tx + tw / 2, ty, 1)
    check(slider.dragging and Options.group.capture == slider, "Slider capture missing")
    Options:mousemoved(tx + tw + 100, area.y + area.h + 100)
    check(slider.value == 1, "Captured slider stopped outside viewport")
    local scrollY = area.scrollY
    Options:wheelmoved(0, -2)
    check(area.scrollY == scrollY, "Wheel scrolled during slider drag")
    Options:selectTab(3)
    check(not slider.dragging and not Options.group.capture, "Tab switch left drag active")
    check(Settings.load().musicVolume == 1, "Interrupted slider drag did not persist")

    Options:selectTab(1)
    focus(slider)
    tx, ty, tw = slider:trackRect()
    Options:mousepressed(tx + tw / 2, ty, 1)
    Options:openDialog(Options.unappliedDialog)
    check(not slider.dragging and not Options.group.capture, "Modal opening left a drag active")
    Options:keypressed("escape")
    Options:selectTab(3)

    Options.msaaSelector:adjust(1)
    Options:goBack()
    check(Options:activeDialog() ~= nil, "Missing leave dialog")
    local index, offset = Options.group.index, area.scrollY
    Options:wheelmoved(0, -5)
    Options:keypressed("tab")
    check(Options.group.index == index and area.scrollY == offset, "Modal leaked input")
    Options:keypressed("escape")
    check(Options:isDirty() and not Options:activeDialog(), "Cancel lost pending edits")

    -- ScrollArea must restore an existing scissor, not clear it globally.
    love.graphics.setScissor(10, 20, 300, 200)
    area:draw()
    local x, y, w, h = love.graphics.getScissor()
    check(x == 10 and y == 20 and w == 300 and h == 200, "Scissor was not restored")
    love.graphics.setScissor()

    fresh()
    Options.settings.res_x, Options.settings.res_y = 900, 650
    Options:resize()
    check(not Options:isDirty(), "Untouched resolution became dirty on window resize")
    Options.resolutionSelector:adjust(1)
    local pending = Options.resolutionSelector:selected()
    Options.settings.res_x, Options.settings.res_y = 1000, 700
    Options:resize()
    local selected = Options.resolutionSelector:selected()
    check(selected[1] == pending[1] and selected[2] == pending[2], "Resize overwrote explicit pending resolution")
end

local function smoothScrollChecks()
    resize(800, 600)
    fresh()
    Options:selectTab(3)
    UI.Motion.setReduced(false)
    local area = Options.scroll
    local goal = area.maxScroll / 2
    check(goal > 0, "Smooth-scroll fixture must overflow")
    area:setScroll(0)
    Options:mousemoved(area.x + 10, area.y + 10)
    Options:wheelmoved(0, -0.25)
    local firstTarget = area.targetY
    check(firstTarget > 0 and area.scrollY == 0, "Wheel jumped instead of easing")
    Options:wheelmoved(0, -0.25)
    check(area.targetY > firstTarget, "Rapid wheel input did not accumulate")
    Options:update(1 / 60)
    check(area.scrollY > 0 and area.scrollY < area.targetY, "Missing intermediate scroll position")
    local widget = area.widgets[1]
    check(near(widget.y, area.y + area.offsets[widget].y - area.scrollY), "Hitboxes do not follow animation")

    area:setScroll(0)
    area:setScroll(goal, true)
    for _ = 1, 6 do area:update(1 / 60) end
    local at60 = area.scrollY
    area:setScroll(0)
    area:setScroll(goal, true)
    for _ = 1, 3 do area:update(1 / 30) end
    check(near(at60, area.scrollY), "Scroll speed depends on frame rate")
    local previous = area.scrollY
    area:setScroll(0, true)
    area:update(1 / 60)
    check(area.scrollY >= 0 and area.scrollY < previous, "Reversing direction overshoots or keeps moving forward")

    area:setScroll(goal, true)
    Options:mousepressed(area.x + 1, area.y + 1, 2)
    previous = area.scrollY
    Options:update(1)
    check(area.scrollY == previous and area.targetY == previous, "Content kept moving during pointer interaction")
    area:setScroll(goal, true)
    Options:openDialog(Options.unappliedDialog)
    previous = area.scrollY
    Options:update(0.1)
    check(area.scrollY == previous and area.targetY == previous, "Content kept moving behind a modal")
    Options:keypressed("escape")

    area:setScroll(0)
    focus(Options.displaySelector)
    Options:keypressed("pagedown")
    check(area.targetY > 0 and area.scrollY == 0, "Page Down did not ease")
    Options:update(1)
    check(area.scrollY == area.targetY, "Scroll never settles exactly")
    local focused = Options.group:focused()
    check(focused.y >= area.y and focused.y + focused.h <= area.y + area.h + 0.01, "Page Down left focus clipped")
    area:setScroll(0)
    for i, widget in ipairs(Options.group.widgets) do
        if widget == area.widgets[#area.widgets] then Options.group:setFocus(i, true); break end
    end
    Options:revealFocus(true)
    check(area.targetY > 0 and area.scrollY == 0, "Focus reveal did not ease")
    UI.Motion.setReduced(true)
    Options:update(1 / 60)
    check(area.scrollY == area.targetY, "Reduced motion did not finish the in-flight scroll")
    area:setScroll(0, true)
    check(area.scrollY == 0, "Reduced motion still animates scrolling")
    UI.Motion.setReduced(false)
    area:setScroll(goal, true)
    local bx, by, bw, bh = area:thumbRect()
    Options:mousepressed(bx + bw / 2, by + bh / 2, 1)
    Options:mousemoved(bx, area.y + area.h + 100)
    Options:mousereleased(bx, area.y + area.h + 100, 1)
    check(area.scrollY == area.maxScroll and area.targetY == area.scrollY, "Scrollbar drag acquired animation lag")
    area:setScroll(0, true)
    Options:layout()
    check(area.targetY == area.scrollY, "Relayout retained a stale animation target")
end

local function transactionChecks()
    local apply = Settings.applyGraphics
    local destination, driver
    Settings.applyGraphics = function(settings)
        driver = Options:graphicsSnapshot()
        Options:resize()
        return true
    end
    local fade = StateManager.fadeTo
    StateManager.fadeTo = function(name) destination = name end
    fresh()
    check(not Options:isDirty() and not Options.applyButton.enabled, "False initial dirty state")
    for tab = 1, 3 do Options:selectTab(tab); check(not Options:isDirty(), "Tab creates edits") end
    Options.msaaSelector:adjust(1)
    Options.msaaSelector:adjust(-1)
    check(not Options:isDirty(), "Restoring value does not clear dirty state")
    Options.showNebulaToggle:activate()
    Options.uncapFpsToggle:activate()
    check(not Options:isDirty(), "Immediate setting enables Apply")

    Options.msaaSelector:adjust(1)
    Options.musicVolumeSlider:adjust(-1)
    local music = Options.settings.musicVolume
    Options:goBack()
    Options:keypressed("return") -- Discard is first.
    check(destination == "mainMenu" and not Options:isDirty(), "Discard did not leave cleanly")
    check(Settings.load().musicVolume == music, "Discard reverted immediate setting")

    for _, result in ipairs({ "keep", "revert", "escape", "timeout" }) do
        fresh()
        Options:selectTab(3)
        destination = nil
        local previous = Options:graphicsSnapshot()
        Options.msaaSelector:adjust(1)
        Options.vsyncToggle:activate()
        local pendingMsaa = Options.pending.msaa
        Options:selectTab(1)
        check(Options:isDirty() and Options.applyButton.enabled, "Tab switch lost pending edits")
        focus(Options.applyButton)
        Options:keypressed("return")
        check(driver.msaa == pendingMsaa and Options.revertDialog:isOpen(), "Apply from Audio failed")
        if result == "keep" then
            Options:keypressed("right"); Options:keypressed("return")
            check(Settings.load().msaa == pendingMsaa, "Keep did not persist")
        elseif result == "revert" then Options:keypressed("return")
        elseif result == "escape" then Options:keypressed("escape")
        else Options:update(10.1) end
        if result ~= "keep" then check(driver.msaa == previous.msaa and driver.vsync == previous.vsync, "Revert did not restore graphics") end
        check(not Options:activeDialog() and not Options:isDirty() and destination == nil, "Confirmation ended incorrectly")
    end

    fresh()
    Options.msaaSelector:adjust(1)
    Options:goBack()
    Options:keypressed("right"); Options:keypressed("return")
    check(Options.revertDialog:isOpen(), "Apply from leave prompt failed")
    Options:keypressed("right"); Options:keypressed("return")
    check(destination == "mainMenu", "Apply/Keep from leave did not return")
    for _, result in ipairs({ "revert", "timeout" }) do
        fresh()
        destination = nil
        Options.msaaSelector:adjust(1)
        Options:goBack()
        Options:keypressed("right"); Options:keypressed("return")
        if result == "revert" then Options:keypressed("return") else Options:update(10.1) end
        check(not destination and not Options:activeDialog() and not Options.leaveAfterApply,
            "Reverting from leave prompt exited or left a queued exit")
    end
    Settings.applyGraphics, StateManager.fadeTo = apply, fade
end

-- Exercise the real Settings transaction code using a controllable window API.
-- This verifies failure and persistence paths, not a physical display driver.
local function displayTransactionChecks()
    local saved = {}
    for _, key in ipairs({ "getMode", "setMode", "getDesktopDimensions", "getFullscreenModes", "getDisplayCount" }) do
        saved[key] = love.window[key]
    end
    local savedResize, write = love.resize, love.filesystem.write
    local dw, dh, flags, behavior, displays, calls
    local function copy(t) local r = {}; for k, v in pairs(t) do r[k] = v end; return r end
    local function disk() return assert(love.filesystem.load(Settings.FILENAME))() end
    local function same(a, b)
        for key, value in pairs(Settings.graphicsSnapshot(a)) do
            if b[key] ~= value then return false end
        end
        return true
    end
    love.window.getDesktopDimensions = function(display) return display == 2 and 1280 or 1920, display == 2 and 720 or 1080 end
    love.window.getDisplayCount = function() return displays end
    love.window.getFullscreenModes = function() return { { width = 1280, height = 720 }, { width = 1920, height = 1080 } } end
    love.window.getMode = function() return dw, dh, copy(flags) end
    love.window.setMode = function(w, h, requested)
        calls = calls + 1
        if behavior == "rejectAll" then return false, "Rejected" end
        if behavior == "rejectOnce" then behavior = nil; return false, "Rejected" end
        if behavior == "throwOnce" then behavior = nil; error("Driver failure") end
        flags = copy(requested)
        dw, dh = w, h
        if flags.fullscreen and flags.fullscreentype == "desktop" then dw, dh = love.window.getDesktopDimensions(flags.display) end
        if behavior == "downgrade" then flags.msaa = 2; behavior = nil end
        -- A driver may send resize before setMode returns. It must not save or
        -- overwrite partially applied settings during that callback.
        Settings.trackWindowResize(Options.settings, dw - 20, dh - 20)
        return true
    end
    love.resize = function(w, h)
        Settings.trackWindowResize(Options.settings, w, h)
        Options:resize()
    end
    local function reset()
        dw, dh = love.graphics.getDimensions()
        flags = { fullscreen = false, display = 1, msaa = 4, vsync = 0, minwidth = 800, minheight = 600 }
        displays, behavior, calls = 2, nil, 0
        I18n.setLanguage("en")
        fresh()
        Options:selectTab(3)
        Settings.save(Options.settings)
    end
    reset()
    check(Options.tabs[3].widgets[1] == Options.displaySelector
        and Options.tabs[3].widgets[2] == Options.windowModeSelector
        and Options.tabs[3].widgets[3] == Options.resolutionSelector, "Display controls are out of order")
    check(Options.tabs[3].widgets[4] == Options.msaaSelector
        and Options.tabs[3].widgets[5] == Options.showNebulaToggle
        and Options.tabs[3].widgets[6] == Options.vsyncToggle
        and Options.tabs[3].widgets[7] == Options.uncapFpsToggle, "Graphics grouping changed or lost controls")

    displays = 1 -- single-monitor: same read-only-value-explanation contract as borderless resolution
    fresh()
    Options:selectTab(3)
    check(Options.displaySelector.readOnly and not Options.displaySelector:isInteractive(),
        "Single monitor should be read-only")
    check(Options.displaySelector:displayText():find(I18n.t("options.note.monitor"), 1, true) ~= nil,
        "Read-only monitor's own value doesn't show the explanation")
    reset()

    Options.windowModeSelector:adjust(1) -- borderless
    local desktop = Options.resolutionSelector:selected()
    check(Options.resolutionSelector.readOnly and not Options.resolutionSelector:isInteractive()
        and desktop[1] == 1920 and desktop[2] == 1080, "Borderless does not show the selected desktop")
    -- Read-only rows can never be focused (keyboard/mouse both skip them), so
    -- their explanation has to live in the rendered value itself.
    check(Options.resolutionSelector:displayText():find(I18n.t("options.note.borderless"), 1, true) ~= nil,
        "Read-only resolution's own value doesn't show the explanation")
    Options.displaySelector:adjust(1)
    desktop = Options.resolutionSelector:selected()
    check(desktop[1] == 1280 and desktop[2] == 720, "Borderless resolution did not follow the monitor")
    Options.windowModeSelector:adjust(1) -- exclusive, prior custom 800x600 is not a reported mode
    local selected = Options.resolutionSelector:selected()
    check(not Options.resolutionSelector.readOnly and Options.resolutionAdjusted
        and selected[1] == 1920 and selected[2] == 1080, "Unsupported fullscreen resolution was retained")
    Options:applyPending()
    check(Options.revertDialog:isOpen(), "Exclusive mode did not open confirmation")
    Options:keypressed("escape")
    check(Options.settings.windowMode == "windowed", "Exclusive mode did not revert")

    reset()
    local baseline = copy(Options.settings)
    Options.msaaSelector:adjust(1)
    behavior = "downgrade"
    Options:applyPending()
    check(Options.previewAdjusted and Options.settings.msaa == 2 and Options.revertDialog:isOpen(), "Driver downgrade was not surfaced")
    check(Options.revertDialog:messageText():find(I18n.t("options.adjustedGraphics"), 1, true), "Confirmation omits fallback explanation")
    check(same(disk(), baseline), "setMode/resize saved an unconfirmed configuration")
    dw, dh = 900, 650
    love.resize(dw, dh)
    Options.settings.musicVolume = 0.25
    Settings.save(Options.settings)
    check(same(disk(), baseline) and disk().musicVolume == 0.25, "Another save path leaked preview graphics or lost audio changes")
    check(same(Settings.load(), baseline), "Restart during preview would load unconfirmed graphics")
    Options:keypressed("right"); Options:keypressed("return")
    check(disk().msaa == 2 and disk().res_x == 900 and disk().res_y == 650, "Keep did not save actual granted dimensions/MSAA")
    check(not Options:isDirty() and not Options.applyButton.enabled, "Resize during confirmation left stale pending edits after Keep")

    for _, failure in ipairs({ "rejectOnce", "throwOnce", "rejectAll" }) do
        reset()
        baseline = copy(Options.settings)
        Options.msaaSelector:adjust(1)
        behavior = failure
        Options:applyPending()
        check(Options.errorDialog:isOpen() and not Options.revertDialog:isOpen(), "Failed mode change has no usable error dialog")
        check(same(disk(), baseline), "Failed mode change overwrote confirmed settings")
        check(Options.settings.res_x == dw and Options.settings.res_y == dh and Options.settings.msaa == flags.msaa,
            "Failed recovery does not show the actual runtime state")
        Options:keypressed("escape")
    end

    reset()
    Options.settings.display, flags.display = 2, 2
    Options:resetPending()
    Settings.save(Options.settings)
    baseline = copy(Options.settings)
    Options.msaaSelector:adjust(1)
    displays = 1 -- unplugged between editing and Apply
    Options:applyPending()
    check(Options.graphicsError == "recovery" and Options.settings.display == 1
        and Options.settings.windowMode == "windowed", "Missing display did not recover to primary window")
    Settings.save(Options.settings)
    check(same(disk(), baseline), "Unconfirmed recovery replaced the confirmed startup configuration")
    Options:keypressed("escape")

    reset()
    baseline = copy(Options.settings)
    Options.msaaSelector:adjust(1)
    Options:applyPending()
    love.filesystem.write = function() return false, "Disk full" end
    Options:keypressed("right"); Options:keypressed("return")
    love.filesystem.write = write
    check(Options.graphicsError == "saveFailed" and same(Options.settings, baseline), "Failed Keep did not revert graphics")
    check(same(disk(), baseline), "Failed Keep overwrote the confirmed file")
    Options:keypressed("escape")

    -- Configuration loading must work before love.window exists at startup.
    local window = love.window
    love.window = nil
    local ok, loaded = pcall(Settings.load)
    love.window = window
    check(ok and loaded.msaa == baseline.msaa, "Saved settings fail during love.conf")
    for key, value in pairs(saved) do love.window[key] = value end
    love.resize = savedResize
end

function love.load()
    local ok, err = xpcall(function()
        UI.Theme.rescale()
        UI.Cursor.init()
        I18n.load()
        for key in pairs(UI.Sfx) do if type(UI.Sfx[key]) == "function" then UI.Sfx[key] = function() end end end
        fresh()
        check(#Options.settingInventory == 16, "Settings missing from inventory")
        layoutChecks()
        inputChecks()
        smoothScrollChecks()
        transactionChecks()
        displayTransactionChecks()
        local desktop = love.window.getDesktopDimensions
        love.window.getDesktopDimensions = function() return 640, 480 end
        local w, h = Limits.windowSize(1280, 720, 1)
        check(w == 640 and h == 480, "Minimum forces window beyond a small desktop")
        love.window.getDesktopDimensions = desktop
        print("PASS: " .. checks .. " UI checks (real fonts/rendering; simulated display transactions)")
        print("Screenshots: " .. love.filesystem.getSaveDirectory())
    end, debug.traceback)
    if not ok then print(err) end
    love.event.quit(ok and 0 or 1)
end
