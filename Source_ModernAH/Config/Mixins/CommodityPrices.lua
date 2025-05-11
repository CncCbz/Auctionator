AuctionatorConfigCommodityPricesFrameMixin = CreateFromMixins(AuctionatorPanelConfigMixin)

function AuctionatorConfigCommodityPricesFrameMixin:OnLoad()
  Auctionator.Debug.Message("AuctionatorConfigCommodityPricesFrameMixin:OnLoad()")

  self.name = "商品最大价格"
  self.parent = "Auctionator"

  self:SetupPanel()
end

function AuctionatorConfigCommodityPricesFrameMixin:OnShow()
  self.ScrollBox:SetVerticalScroll(0)
  self:ShowSettings()

  self.CommodityBuyShortcut:SetShortcut(Auctionator.Config.Get(Auctionator.Config.Options.COMMODITY_BUY_SHORTCUT))
  self.CommodityConfirmShortcut:SetShortcut(Auctionator.Config.Get(Auctionator.Config.Options.COMMODITY_CONFIRM_SHORTCUT))
end

function AuctionatorConfigCommodityPricesFrameMixin:ShowSettings()
  self.maxPrices = Auctionator.Config.Get(Auctionator.Config.Options.COMMODITY_MAX_PRICES) or {}
  
  -- 清空滚动框
  if self.ScrollBox and self.ScrollBox.ScrollFrame then
    local content = self.ScrollBox.ScrollFrame.Content
    for _, child in ipairs({content:GetChildren()}) do
      if child ~= self.CommodityBuyShortcut and child ~= self.ItemID and child ~= self.MaxPrice and child ~= self.AddButton then
        child:Hide()
        child:SetParent(nil)
      end
    end
  end
  
  -- 初始化输入框
  self.ItemID:SetText("")
  self.MaxPrice:SetAmount(0)
  
  -- 显示现有价格设置
  local yOffset = -80
  for itemID, maxPrice in pairs(self.maxPrices) do
    local itemName, itemLink = GetItemInfo(itemID)
    
    if itemName then
      local row = CreateFrame("Frame", nil, self.ScrollBox.ScrollFrame.Content)
      row:SetSize(570, 20)
      row:SetPoint("TOPLEFT", self.ScrollBox.ScrollFrame.Content, "TOPLEFT", 0, yOffset)
      
      row.ItemIDText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      row.ItemIDText:SetText(itemID)
      row.ItemIDText:SetPoint("LEFT", row, "LEFT", 20, 0)
      row.ItemIDText:SetWidth(80)
      
      row.ItemNameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      row.ItemNameText:SetText(itemName)
      row.ItemNameText:SetPoint("LEFT", row.ItemIDText, "RIGHT", 10, 0)
      row.ItemNameText:SetWidth(180)
      
      row.MaxPriceText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      row.MaxPriceText:SetText(GetMoneyString(maxPrice, true))
      row.MaxPriceText:SetPoint("LEFT", row.ItemNameText, "RIGHT", 10, 0)
      row.MaxPriceText:SetWidth(120)
      
      row.DeleteButton = CreateFrame("Button", nil, row, "UIPanelCloseButton")
      row.DeleteButton:SetPoint("LEFT", row.MaxPriceText, "RIGHT", 10, 0)
      row.DeleteButton:SetSize(20, 20)
      row.DeleteButton.itemID = itemID
      row.DeleteButton:SetScript("OnClick", function(button)
        self:DeleteMaxPrice(button.itemID)
      end)
      
      yOffset = yOffset - 25
    end
  end
end

function AuctionatorConfigCommodityPricesFrameMixin:DeleteMaxPrice(itemID)
  if self.maxPrices[itemID] then
    self.maxPrices[itemID] = nil
    Auctionator.Config.Set(Auctionator.Config.Options.COMMODITY_MAX_PRICES, self.maxPrices)
    self:ShowSettings()
  end
end

function AuctionatorConfigCommodityPricesFrameMixin:AddMaxPrice()
  local itemID = tonumber(self.ItemID:GetText())
  local maxPrice = self.MaxPrice:GetAmount()
  
  if itemID and maxPrice and maxPrice > 0 then
    local itemName = GetItemInfo(itemID)
    if itemName then
      self.maxPrices[itemID] = maxPrice
      Auctionator.Config.Set(Auctionator.Config.Options.COMMODITY_MAX_PRICES, self.maxPrices)
      self:ShowSettings()
    end
  end
end

function AuctionatorConfigCommodityPricesFrameMixin:Save()
  Auctionator.Debug.Message("AuctionatorConfigCommodityPricesFrameMixin:Save()")
  
  Auctionator.Config.Set(Auctionator.Config.Options.COMMODITY_BUY_SHORTCUT, self.CommodityBuyShortcut:GetShortcut())
  Auctionator.Config.Set(Auctionator.Config.Options.COMMODITY_CONFIRM_SHORTCUT, self.CommodityConfirmShortcut:GetShortcut())
end

function AuctionatorConfigCommodityPricesFrameMixin:Cancel()
  Auctionator.Debug.Message("AuctionatorConfigCommodityPricesFrameMixin:Cancel()")
end 