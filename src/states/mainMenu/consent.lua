--- First-run sharing questions, asked one after another.
-- Acts like one dialog: forwards input to the current one.

local Consent = require("services.consent")
local I18n = require("core.i18n")
local Presence = require("services.presence")
local Stats = require("services.stats")
local UI = require("ui")

local ConsentQueue = {}
ConsentQueue.__index = ConsentQueue

-- asked in this order; key is the i18n group
local QUESTIONS = {
    { key = "statsConsent", asked = "statsConsentAsked", answer = Stats.setConsent },
    { key = "presenceConsent", asked = "presenceConsentAsked", answer = Presence.setConsent },
}

---@param settings table
---@param question table
---@return table # a UI.Dialog
local function buildDialog(settings, question)
    local dialog
    local function text(name)
        return function() return I18n.t("menu." .. question.key .. "." .. name) end
    end
    local function answer(enabled)
        question.answer(settings, enabled)
        dialog:close()
    end

    dialog = UI.Dialog.new{
        title = text("title"),
        message = text("message"),
        buttons = {
            { label = text("decline"), onSelect = function() answer(false) end },
            { label = text("accept"), onSelect = function() answer(true) end },
        },
        onCancel = function() answer(false) end,
    }
    dialog:onFocusChanged(UI.Sfx.focus)
    return dialog
end

---@param settings table
---@return table
function ConsentQueue.new(settings)
    local self = setmetatable({ settings = settings, entries = {}, current = nil }, ConsentQueue)
    for i, question in ipairs(QUESTIONS) do
        self.entries[i] = { question = question, dialog = buildDialog(settings, question) }
    end
    return self
end

--- opens the next unanswered question, if any
function ConsentQueue:advance()
    if self.current and self.current:isOpen() then return end
    self.current = nil
    for _, entry in ipairs(self.entries) do
        if Consent.pending(self.settings, entry.question.asked) then
            self.current = entry.dialog
            return self.current:openDialog()
        end
    end
end

---@return boolean
function ConsentQueue:isOpen()
    return self.current ~= nil and self.current:isOpen()
end

function ConsentQueue:layout()
    for _, entry in ipairs(self.entries) do entry.dialog:layout() end
end

--- forwards to the open dialog, then moves on if answered
---@param method string
local function forward(method)
    return function(self, ...)
        if not self:isOpen() then return false end
        local result = self.current[method](self.current, ...)
        self:advance()
        return result
    end
end

ConsentQueue.update = forward("update")
ConsentQueue.keypressed = forward("keypressed")
ConsentQueue.mousemoved = forward("mousemoved")
ConsentQueue.mousepressed = forward("mousepressed")
ConsentQueue.mousereleased = forward("mousereleased")

---@return boolean hovering
---@return boolean danger
function ConsentQueue:hovering(x, y)
    if not self:isOpen() then return false, false end
    return self.current:hovering(x, y)
end

function ConsentQueue:draw()
    if self:isOpen() then self.current:draw() end
end

return ConsentQueue
