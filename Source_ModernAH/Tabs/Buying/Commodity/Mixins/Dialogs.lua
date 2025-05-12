AuctionatorBuyCommodityWidePriceRangeWarningDialogMixin = {}

function AuctionatorBuyCommodityWidePriceRangeWarningDialogMixin:OnHide()
  self:Hide()
end

function AuctionatorBuyCommodityWidePriceRangeWarningDialogMixin:SetDetails(details)
  self.PurchaseDetails:SetText(
    RED_FONT_COLOR:WrapTextInColorCode(AUCTIONATOR_L_CAREFUL_CAPS) .. "\n\n" ..
    AUCTIONATOR_L_PRICE_VARIES_WARNING .. "\n\n" ..
    AUCTIONATOR_L_UNIT_PRICE_RANGE:format(
      GetMoneyString(details.minUnitPrice, true),
      GetMoneyString(details.maxUnitPrice, true)
    )
  )
  self:Show()
end

function AuctionatorBuyCommodityWidePriceRangeWarningDialogMixin:StartPurchase()
  self:GetParent():ForceStartPurchase()
  self:Hide()
end

AuctionatorBuyCommodityFinalConfirmationDialogMixin = {}

function AuctionatorBuyCommodityFinalConfirmationDialogMixin:OnHide()
  self:Hide()
  if self.purchasePending then
    C_AuctionHouse.CancelCommoditiesPurchase()
    self.purchasePending = false
  end
end

function AuctionatorBuyCommodityFinalConfirmationDialogMixin:SetDetails(details)
  self.itemID = details.itemID
  self.quantity = details.quantity
  self.unitPrice = details.unitPrice  -- 存储单价
  self.PurchaseDetails:SetText(details.prefix .. AUCTIONATOR_L_CONFIRM_PURCHASE_OF_X_FOR_X
    :format(Auctionator.Utilities.CreateCountString(details.quantity),
      GetMoneyString(details.total, true)) .. "\n\n" ..
    AUCTIONATOR_L_BRACKETS_X_EACH:format(GetMoneyString(details.unitPrice, true))
    )
  self.purchasePending = true
  self:Show()
  self:SetPropagateKeyboardInput(false)
  self:SetFrameStrata("DIALOG")
  self:EnableKeyboard(true)
end

function AuctionatorBuyCommodityFinalConfirmationDialogMixin:ConfirmPurchase()
  print("确认购买")
  C_AuctionHouse.ConfirmCommoditiesPurchase(self.itemID, self.quantity)
  self.purchasePending = false
  self:Hide()
  -- 一行黄色打印购买商品的id和数量和价格
  print("|cffff0000购买商品的id: " .. self.itemID .. " 数量: " .. self.quantity .. " 价格: " .. GetMoneyString(self.unitPrice, true) .. "|r")
end

function AuctionatorBuyCommodityFinalConfirmationDialogMixin:OnKeyDown(key)
  if key == "ENTER" or key == Auctionator.Config.Get(Auctionator.Config.Options.COMMODITY_CONFIRM_SHORTCUT) then
    self:ConfirmPurchase()
  elseif key == "ESCAPE" then
    self:Hide()
  end
end

AuctionatorBuyCommodityQuantityCheckConfirmationDialogMixin = {}

function AuctionatorBuyCommodityQuantityCheckConfirmationDialogMixin:OnHide()
  self:Hide()
  if self.purchasePending then
    C_AuctionHouse.CancelCommoditiesPurchase()
  end
end

function AuctionatorBuyCommodityQuantityCheckConfirmationDialogMixin:SetDetails(details)
  self.itemID = details.itemID
  self.quantity = details.quantity
  self.PurchaseDetails:SetText(
    details.prefix ..
    details.message:format(GetMoneyString(details.total, true), GetMoneyString(details.unitPrice, true))
    .. "\n\n" ..
    AUCTIONATOR_L_ENTER_QUANTITY_TO_CONFIRM_PURCHASE:format(self.quantity)
    )
  self.QuantityInput:SetText("")
  self.purchasePending = true
  self:Show()
  self.QuantityInput:SetFocus()
  self:SetPropagateKeyboardInput(false)
  self:SetFrameStrata("DIALOG")
  self:EnableKeyboard(true)
end

function AuctionatorBuyCommodityQuantityCheckConfirmationDialogMixin:ConfirmPurchase()
  if tonumber(self.QuantityInput:GetText()) == self.quantity then
    C_AuctionHouse.ConfirmCommoditiesPurchase(self.itemID, self.quantity)
    self.purchasePending = false
    self:Hide()
  end
end

function AuctionatorBuyCommodityQuantityCheckConfirmationDialogMixin:OnKeyDown(key)
  if key == "ENTER" or key == Auctionator.Config.Get(Auctionator.Config.Options.COMMODITY_CONFIRM_SHORTCUT) then
    self:ConfirmPurchase()
  elseif key == "ESCAPE" then
    self:Hide()
  end
end
