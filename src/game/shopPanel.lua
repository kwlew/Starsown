--- The buy/sell overlay opened by talking to a shop NPC (see game/npcs.lua's
-- `interaction = "shop"` and game/shops.lua). Two columns, one row per
-- listing: click a "buy" row to purchase one unit, click a "sell" row to
-- sell one unit from the bag. Built the same way InventoryPanel is -- its own
-- layout()/draw()/mousepressed(), no keyboard focus -- closing is
-- states/play.lua's job (Escape, or walking away from the NPC).
--
-- `wallet` decouples this from Play's own currency field: { get = fun():
-- number, spend = fun(amount), earn = fun(amount) }, built once in
-- Play:newGame alongside the Inventory this panel shares with the bag.

local Theme = require "ui.core.theme"
local Items = require "game.items"
local Shape = require "game.shape"
local Shops = require "game.shops"
local Label = require "ui.text.label"
local Format = require "utils.format"
local I18n = require "core.i18n"
local Sfx = require "ui.core.sfx"

local Panel = {}
Panel.__index = Panel

local ROW_H = 46
local ROW_GAP = 6
local COL_W = 230
local COL_GAP = 24
local PAD = 18
local TITLE_GAP = 10
local WALLET_GAP = 8
local HEADER_GAP = 8
local ICON_INSET = 6    -- gap between a row's left edge and its icon
local ICON_RATIO = 0.34 -- of the row height
local PRICE_W = 60      -- reserved width for the right-aligned price column
local NAME_GAP = 8      -- gap between the icon and the name text

local EMPTY_SPEC = { buy = {}, sell = {} } -- an unresolved shopId degrades to no listings, not an error

---@param inventory table # the player's Inventory; bought items land here, sold ones come from here
---@param wallet table # { get: fun():number, spend: fun(amount:number), earn: fun(amount:number) }
---@return table
function Panel.new(inventory, wallet)
    local self = setmetatable({
        inventory = inventory,
        wallet = wallet,
        open = false,
        shopId = nil,
        title = "",
        hovered = nil, -- { list: "buy"|"sell", index: integer }
        bounds = { x = 0, y = 0, w = 0, h = 0 },
    }, Panel)
    self:layout()
    return self
end

---@return boolean
function Panel:isOpen()
    return self.open
end

--- shows one shop's listings under the given title (already resolved --
-- this module has no opinion on where a name comes from)
---@param shopId string
---@param title? string # defaults to a generic "Shop" heading
function Panel:openPanel(shopId, title)
    self.shopId = shopId
    self.title = title or I18n.t("game.shop.title")
    self.open = true
    self.hovered = nil
    self:layout()
end

function Panel:close()
    self.open = false
    self.hovered = nil
end

---@return table # { buy: table[], sell: table[] }
function Panel:spec()
    return Shops.get(self.shopId) or EMPTY_SPEC
end

--- centres the panel; call on open and on resize. Sized to whichever column
-- has more rows, so a lopsided shop (all sell, no buy) doesn't leave the
-- shorter column's empty space unaccounted for.
function Panel:layout()
    local pad, colGap = Theme.px(PAD), Theme.px(COL_GAP)
    local colW = Theme.px(COL_W)
    local titleFont, bodyFont = Theme.font("button"), Theme.font("body")
    local titleHeight = titleFont:getHeight() + Theme.px(TITLE_GAP)
    -- the wallet line and the column headers share the "body" role, so one
    -- height covers both rows
    local walletHeight = bodyFont:getHeight() + Theme.px(WALLET_GAP)
    local headerHeight = bodyFont:getHeight() + Theme.px(HEADER_GAP)

    local spec = self:spec()
    local rows = math.max(#spec.buy, #spec.sell, 1)

    self.colW = colW
    self.rowH, self.rowGap = Theme.px(ROW_H), Theme.px(ROW_GAP)

    local bounds = self.bounds
    bounds.w = colW * 2 + colGap + pad * 2
    bounds.h = pad * 2 + titleHeight + walletHeight + headerHeight
        + rows * self.rowH + (rows - 1) * self.rowGap
    bounds.x = (love.graphics.getWidth() - bounds.w) / 2
    bounds.y = (love.graphics.getHeight() - bounds.h) / 2

    self.walletY = bounds.y + pad + titleHeight
    self.headerY = self.walletY + walletHeight
    self.listY = self.headerY + headerHeight
    self.buyX = bounds.x + pad
    self.sellX = self.buyX + colW + colGap
end

--- top-left of one row, in screen space
---@param list "buy"|"sell"
---@param index integer # 1-based
---@return number x
---@return number y
function Panel:rowOrigin(list, index)
    local x = list == "buy" and self.buyX or self.sellX
    return x, self.listY + (index - 1) * (self.rowH + self.rowGap)
end

---@param x number
---@param y number
---@return "buy"|"sell"|nil list
---@return integer|nil index
---@return table|nil entry
function Panel:rowAt(x, y)
    local spec = self:spec()
    for _, list in ipairs({ "buy", "sell" }) do
        for index, entry in ipairs(spec[list]) do
            local rx, ry = self:rowOrigin(list, index)
            if Theme.pointIn(x, y, rx, ry, self.colW, self.rowH) then
                return list, index, entry
            end
        end
    end
    return nil
end

---@param x number
---@param y number
function Panel:mousemoved(x, y)
    local list, index = self:rowAt(x, y)
    self.hovered = list and { list = list, index = index } or nil
end

---@return boolean # whether the point is over the panel at all
function Panel:hovering(x, y)
    return Theme.pointIn(x, y, self.bounds.x, self.bounds.y, self.bounds.w, self.bounds.h)
end

--- true while the pointer sits over a row that would actually do something if
-- clicked right now -- the cursor's hover state reads this rather than the
-- raw geometric hover, so parking over a row you can't afford doesn't look
-- clickable
---@return boolean
function Panel:hoveredAffordable()
    local hovered = self.hovered
    if not hovered then return false end
    return self:affordable(hovered.list, self:spec()[hovered.list][hovered.index])
end

--- buys one unit: charges the wallet only if there was room for it, so a full
-- bag can't take payment for nothing
---@param entry table # { id: string, price: number }
function Panel:buy(entry)
    if not Items.get(entry.id) then return end
    if self.wallet.get() < entry.price then return end

    local leftover = self.inventory:add(entry.id, 1)
    if leftover > 0 then return end

    self.wallet.spend(entry.price)
    Sfx.select()
end

--- sells one unit: only if the player actually has one, through the same
-- id-based removal buy() mirrors with add()
---@param entry table # { id: string, price: number }
function Panel:sell(entry)
    if not self.inventory:removeOne(entry.id) then return end
    self.wallet.earn(entry.price)
    Sfx.select()
end

--- left click transacts one unit of whichever row it lands on
---@param x number
---@param y number
---@param button integer
---@return boolean consumed
function Panel:mousepressed(x, y, button)
    local list, index, entry = self:rowAt(x, y)
    self.hovered = list and { list = list, index = index } or nil
    if not list then return false end

    if button == 1 then
        if list == "buy" then self:buy(entry) else self:sell(entry) end
    end
    return true
end

---@param list "buy"|"sell"
---@param entry table # { id: string, price: number }
---@return boolean # whether this row can actually be clicked right now
function Panel:affordable(list, entry)
    if list == "buy" then return self.wallet.get() >= entry.price end
    return self.inventory:count(entry.id) > 0
end

---@param list "buy"|"sell"
---@param font any # a love.Font
function Panel:drawList(list, font)
    local colors = Theme.colors
    local iconRadius = self.rowH * ICON_RATIO
    local inset = Theme.px(ICON_INSET)
    local nameGap, priceW = Theme.px(NAME_GAP), Theme.px(PRICE_W)

    for index, entry in ipairs(self:spec()[list]) do
        local x, y = self:rowOrigin(list, index)
        local ok = self:affordable(list, entry)
        -- only lights up when it's actually clickable, the same rule
        -- Widget:isLit()/isInteractive() apply to a disabled button
        local lit = ok and self.hovered and self.hovered.list == list and self.hovered.index == index
        local alpha = ok and 1 or 0.5

        Theme.setColor(lit and colors.accentDark or colors.panelRaised, alpha)
        love.graphics.rectangle("fill", x, y, self.colW, self.rowH, Theme.metrics.radius)
        Theme.setColor(lit and colors.accent or colors.panelBorder, alpha)
        love.graphics.rectangle("line", x, y, self.colW, self.rowH, Theme.metrics.radius)

        local color = Items.color(entry.id)
        love.graphics.setColor(color[1], color[2], color[3], alpha)
        Shape.draw("fill", x + inset + iconRadius, y + self.rowH / 2, iconRadius, Items.sides(entry.id))

        local nameX = x + inset * 2 + iconRadius * 2 + nameGap
        Label.draw{
            text = Items.name(entry.id),
            x = nameX, y = y + (self.rowH - font:getHeight()) / 2,
            width = self.colW - (nameX - x) - priceW, align = "left",
            font = font, color = colors.text, alpha = alpha,
        }
        Label.draw{
            text = Format.number(entry.price),
            x = x + self.colW - priceW - inset, y = y + (self.rowH - font:getHeight()) / 2,
            width = priceW, align = "right",
            font = font, color = colors.text, alpha = alpha,
        }
    end
end

--- scrim, panel, title, the player's own balance, the two column headers,
-- then their rows -- the balance is drawn here rather than left to the HUD,
-- since Play hides the HUD while this is open (see states/play.lua)
function Panel:draw()
    local colors = Theme.colors
    local bounds = self.bounds
    local pad = Theme.px(PAD)
    local titleFont, bodyFont, rowFont = Theme.font("button"), Theme.font("body"), Theme.font("small")

    Theme.setColor(colors.scrim)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())
    Theme.panel(bounds.x, bounds.y, bounds.w, bounds.h)

    Label.draw{
        text = self.title,
        x = bounds.x, y = bounds.y + pad, width = bounds.w,
        font = titleFont,
    }
    Label.draw{
        text = I18n.t("game.hud.coins", { n = Format.number(self.wallet.get()) }),
        x = bounds.x, y = self.walletY, width = bounds.w,
        font = bodyFont, color = colors.textDim,
    }

    Label.draw{
        text = I18n.t("game.shop.buy"), x = self.buyX, y = self.headerY, width = self.colW,
        align = "left", font = bodyFont, color = colors.textDim,
    }
    Label.draw{
        text = I18n.t("game.shop.sell"), x = self.sellX, y = self.headerY, width = self.colW,
        align = "left", font = bodyFont, color = colors.textDim,
    }

    self:drawList("buy", rowFont)
    self:drawList("sell", rowFont)

    love.graphics.setColor(1, 1, 1, 1)
end

return Panel
