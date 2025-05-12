AuctionatorBuyCommodityFrameTemplateMixin = {}

local SEARCH_EVENTS = {
  "COMMODITY_SEARCH_RESULTS_UPDATED",
  "COMMODITY_PURCHASE_SUCCEEDED",
  "COMMODITY_PURCHASE_FAILED",
}

local PURCHASE_EVENTS = {
  "COMMODITY_PRICE_UPDATED",
  "COMMODITY_PRICE_UNAVAILABLE",
}

function AuctionatorBuyCommodityFrameTemplateMixin:OnLoad()
  self.ResultsListing:Init(self.DataProvider)
  Auctionator.EventBus:Register(self, {
    Auctionator.Buying.Events.ShowCommodityBuy,
    Auctionator.Buying.Events.SelectCommodityRow,
    Auctionator.Shopping.Tab.Events.SearchStart,
  })

  self.DetailsContainer.Quantity:SetScript("OnTextChanged", function(numericInput)
    if numericInput:GetText() == "" then
      self.selectedQuantity = 0
    else
      local value = tonumber(numericInput:GetText())
      if value and value >= 0 then
        if self.maxQuantity then
          value = math.min(value, self.maxQuantity)
        end
        self.selectedQuantity = value
      end
    end
    self:UpdateView()
  end)

  -- 添加按键监听，用于捕获F1快捷键
  self:SetScript("OnKeyDown", function(_, key)
    if key == Auctionator.Config.Get(Auctionator.Config.Options.COMMODITY_BUY_SHORTCUT) then
      self:QuickBuyClicked()
    end
  end)
end

function AuctionatorBuyCommodityFrameTemplateMixin:OnShow()
  self:GetParent().ResultsListing:Hide()
  self:GetParent().ShoppingResultsInset:Hide()
  self:GetParent().ExportCSV:Hide()
  FrameUtil.RegisterFrameForEvents(self, SEARCH_EVENTS)
  
  -- 注册快捷键
  local function SetupBindings()
    if self:IsVisible() then
      -- 移除按钮点击绑定，改为使用脚本运行函数
      -- SetOverrideBinding(self, false, Auctionator.Config.Get(Auctionator.Config.Options.COMMODITY_BUY_SHORTCUT), "CLICK AuctionatorBuyCommodityButton:LeftButton")
      -- 让OnKeyDown处理快捷键，不需要在这里设置绑定
    end
  end
  
  if InCombatLockdown() then
    EventUtil.ContinueAfterAllEvents(SetupBindings, "PLAYER_REGEN_ENABLED")
  else
    SetupBindings()
  end
  
  -- 设置为可以接收按键输入
  self:EnableKeyboard(true)
  self:SetPropagateKeyboardInput(true)
end

function AuctionatorBuyCommodityFrameTemplateMixin:OnHide()
  self:GetParent().ResultsListing:Show()
  self:GetParent().ShoppingResultsInset:Show()
  self:GetParent().ExportCSV:Show()
  self:Hide()
  self.results = nil
  self.maxQuantity = nil
  self.isQuickBuy = false -- 重置快捷键购买标记
  if self.waitingForPurchase then
    FrameUtil.UnregisterFrameForEvents(self, PURCHASE_EVENTS)
    C_AuctionHouse.CancelCommoditiesPurchase()
    self.waitingForPurchase = false
  end
  FrameUtil.UnregisterFrameForEvents(self, SEARCH_EVENTS)
  
  -- 清除快捷键绑定
  ClearOverrideBindings(self)
  
  -- 禁用按键接收
  self:EnableKeyboard(false)
end

function AuctionatorBuyCommodityFrameTemplateMixin:ReceiveEvent(eventName, ...)
  if eventName == Auctionator.Buying.Events.ShowCommodityBuy then
    local rowData, itemKeyInfo = ...

    self:Show()
    self.selectedRows = 1
    self.selectedQuantity = rowData.purchaseQuantity or 1
    local prettyName = AuctionHouseUtil.GetItemDisplayTextFromItemKey(
      rowData.itemKey,
      itemKeyInfo,
      false
    )
    self.expectedItemID = rowData.itemKey.itemID
    self.itemKey = rowData.itemKey
    self.IconAndName:SetItem(rowData.itemKey, nil, itemKeyInfo.quality, prettyName, itemKeyInfo.iconFileID)
    self.IconAndName:SetScript("OnMouseUp", function()
      AuctionHouseFrame:SelectBrowseResult(rowData)
      -- Clear displayMode (prevents bag items breaking in some scenarios)
      AuctionHouseFrame.displayMode = nil
    end)
    self:Search()
    self:UpdateView()
  elseif eventName == Auctionator.Buying.Events.SelectCommodityRow then
    local rows = ...
    self.selectedQuantity = 0
    for _, r in ipairs(self.results) do
      if r.rowIndex <= rows then
        self.selectedQuantity = self.selectedQuantity + r.quantity
      else
        break
      end
    end
    self:UpdateView()
  elseif eventName == Auctionator.Shopping.Tab.Events.SearchStart then
    self:Hide()
  end
end

function AuctionatorBuyCommodityFrameTemplateMixin:OnEvent(eventName, eventData, ...)
  if (eventName == "COMMODITY_SEARCH_RESULTS_UPDATED" and self.expectedItemID ~= nil and
          self.expectedItemID == eventData
        ) then
    self.results = self:ProcessCommodityResults(eventData)
    self.maxQuantity = C_AuctionHouse.GetCommoditySearchResultsQuantity(eventData)
    self.DataProvider:SetListing(self.results)
    self:UpdateView()

  elseif eventName == "COMMODITY_PRICE_UPDATED" and self.results then
    self:CheckPurchase(eventData, ...)

  -- Getting a price to purchase failed
  elseif eventName == "COMMODITY_PRICE_UNAVAILABLE" then
    FrameUtil.UnregisterFrameForEvents(self, PURCHASE_EVENTS)
    self.waitingForPurchase = false
    C_AuctionHouse.CancelCommoditiesPurchase()

    self:Search()

  -- Refresh listing after purchase attempt
  elseif eventName == "COMMODITY_PURCHASE_SUCCEEDED" or
      eventName == "COMMODITY_PURCHASE_FAILED" then
    self:Search()
  end
end

function AuctionatorBuyCommodityFrameTemplateMixin:Search()
  if self.itemKey == nil then
    return
  end
  Auctionator.EventBus
    :RegisterSource(self, "BuyCommodityFrame")
    :Fire(self, Auctionator.Buying.Events.RefreshingCommodities)
    :UnregisterSource(self)
  Auctionator.AH.SendSearchQueryByItemKey(self.itemKey, Auctionator.Constants.CommodityResultsSorts, false)
end

function AuctionatorBuyCommodityFrameTemplateMixin:ProcessCommodityResults(itemID)
  local entries = {}
  local anyOwnedNotLoaded = false

  for index = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) do
    local resultInfo = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, index)
    if resultInfo.owners[1] == "player" then
      resultInfo.owners[1] = GREEN_FONT_COLOR:WrapTextInColorCode(AUCTION_HOUSE_SELLER_YOU)
    end
    local entry = {
      price = resultInfo.unitPrice,
      owners = resultInfo.owners,
      totalNumberOfOwners = resultInfo.totalNumberOfOwners,
      otherSellers = Auctionator.Utilities.StringJoin(resultInfo.owners, PLAYER_LIST_DELIMITER),
      quantity = resultInfo.quantity,
      quantityFormatted = FormatLargeNumber(resultInfo.quantity),
      selected = self.selectedRows >= index,
      rowIndex = index,
    }

    if #entry.owners > 0 and #entry.owners < entry.totalNumberOfOwners then
      entry.otherSellers = AUCTIONATOR_L_SELLERS_OVERFLOW_TEXT:format(entry.otherSellers, entry.totalNumberOfOwners - #entry.owners)
    end

    table.insert(entries, entry)
  end

  return entries
end

function AuctionatorBuyCommodityFrameTemplateMixin:GetPrices()
  local total = 0
  local quantityLeft = self.selectedQuantity
  for _, r in ipairs(self.results) do
    if quantityLeft == 0 then
      break
    elseif r.quantity > quantityLeft then
      total = total + quantityLeft * r.price
      quantityLeft = 0
    else
      total = total + r.price * r.quantity
      quantityLeft = quantityLeft - r.quantity
    end
  end
  local unitPrice = 0
  if self.selectedQuantity > 0 then
    unitPrice = math.ceil(math.ceil(total / self.selectedQuantity / 100) * 100)
  end

  return unitPrice, total
end

function AuctionatorBuyCommodityFrameTemplateMixin:UpdateView()
  if self.DetailsContainer.Quantity:GetText() ~= "" or self.selectedQuantity ~= 0 then
    self.DetailsContainer.Quantity:SetNumber(self.selectedQuantity)
  end
  if self.results then
    local runningQuantity = 0
    for _, r in ipairs(self.results) do
      r.selected = runningQuantity < self.selectedQuantity
      runningQuantity = runningQuantity + r.quantity
    end
    self.DataProvider:SetListing(self.results)

    local unitPrice, total = self:GetPrices()

    self.DetailsContainer.UnitPriceText:SetText(GetMoneyString(unitPrice, true))
    self.DetailsContainer.TotalPriceText:SetText(GetMoneyString(total, true))
    
    -- 显示快捷键提示和最大购买价格
    local maxPricesTable = Auctionator.Config.Get(Auctionator.Config.Options.COMMODITY_MAX_PRICES)
    local maxPrice = maxPricesTable[self.expectedItemID]
    
    if maxPrice then
      self.DetailsContainer.MaxPriceText:SetText("扫货价 ≤: " .. GetMoneyString(maxPrice, true))
      self.DetailsContainer.MaxPriceText:Show()
      -- 设置金币和银币输入框的值
      self.DetailsContainer.MaxPriceGold:SetText(math.floor(maxPrice / 10000))
      self.DetailsContainer.MaxPriceSilver:SetText(math.floor((maxPrice % 10000) / 100))
      self.DetailsContainer.RemoveMaxPriceButton:Enable()
    else
      self.DetailsContainer.MaxPriceText:Hide()
      -- 默认显示当前单价
      local goldValue = math.floor(unitPrice / 10000)
      local silverValue = math.floor((unitPrice % 10000) / 100)
      self.DetailsContainer.MaxPriceGold:SetText(goldValue)
      self.DetailsContainer.MaxPriceSilver:SetText(silverValue)
      self.DetailsContainer.RemoveMaxPriceButton:Disable()
    end
    
    self.DetailsContainer.BuyButton:SetText("购买")
    self.DetailsContainer.BuyButton:SetEnabled(total <= GetMoney())
    self.DetailsContainer.SetMaxPriceButton:Enable()
    self.DetailsContainer.UseCurrentButton:Enable()

  else
    self.DetailsContainer.UnitPriceText:SetText("")
    self.DetailsContainer.TotalPriceText:SetText("")
    self.DetailsContainer.MaxPriceText:Hide()
    self.DetailsContainer.MaxPriceGold:SetText("0")
    self.DetailsContainer.MaxPriceSilver:SetText("0")
    self.DetailsContainer.BuyButton:SetText("购买")
    self.DetailsContainer.BuyButton:Disable()
    self.DetailsContainer.SetMaxPriceButton:Disable()
    self.DetailsContainer.UseCurrentButton:Disable()
    self.DetailsContainer.RemoveMaxPriceButton:Disable()
  end
end

function AuctionatorBuyCommodityFrameTemplateMixin:BuyClicked()
  local minUnitPrice = self.results[1].price
  local maxUnitPrice = self.results[1].price
  for _, r in ipairs(self.results) do
    if not r.selected then
      break
    end
    maxUnitPrice = r.price
  end
  local shift = (maxUnitPrice - minUnitPrice) / minUnitPrice * 100
  if shift >= 50 then
    self.WidePriceRangeWarningDialog:SetDetails({
      minUnitPrice = minUnitPrice,
      maxUnitPrice = maxUnitPrice,
    })
  else
    self:ForceStartPurchase()
  end
end

-- 快捷键购买函数
function AuctionatorBuyCommodityFrameTemplateMixin:QuickBuyClicked()
  if not self.results or not self.DetailsContainer.BuyButton:IsEnabled() then
    print(date("%H:%M:%S") .. " 快捷键购买失败")
    self.isQuickBuy = false -- 重置标记
    return
  end
  
  local minUnitPrice = self.results[1].price
  local maxUnitPrice = self.results[1].price
  for _, r in ipairs(self.results) do
    if not r.selected then
      break
    end
    maxUnitPrice = r.price
  end
  
  -- 检查是否有最大购买价格设置
  local maxPricesTable = Auctionator.Config.Get(Auctionator.Config.Options.COMMODITY_MAX_PRICES)
  local maxPrice = maxPricesTable[self.expectedItemID]
  
  -- 没有设置maxPrice
  if not maxPrice then
    print(date("%H:%M:%S") .. " 没有设置采购价")
    self.isQuickBuy = false -- 重置标记
    return
  end
  
  local hasMaxPrice = (maxPrice ~= nil)
  local isPriceLowerOrEqual = false
  
  if hasMaxPrice then
    isPriceLowerOrEqual = (maxUnitPrice <= maxPrice)
  end
  
  if hasMaxPrice and isPriceLowerOrEqual then
    -- 把数量设置为可购买的最大数量的一半
    -- self.selectedQuantity = math.floor(self.maxQuantity / 2)
    self.isQuickBuy = true -- 添加标记，表示这是快捷键购买
    self:ForceStartPurchase()
    return
  end

  print(date("%H:%M:%S") .. " 价格超过采购价，取消购买")
  self.isQuickBuy = false -- 重置标记
  self:Search()
  return
end

function AuctionatorBuyCommodityFrameTemplateMixin:ForceStartPurchase()
  self.waitingForPurchase = true
  FrameUtil.RegisterFrameForEvents(self, PURCHASE_EVENTS)
  C_AuctionHouse.StartCommoditiesPurchase(self.expectedItemID, self.selectedQuantity)
end

local function GetMedianUnit(quantity, results)
  local target = math.floor(quantity / 2)
  local runningQuantity = 0
  for _, r in ipairs(results) do
    runningQuantity = runningQuantity + r.quantity
    if runningQuantity >= target then
      return r.price
    end
  end
  return results[#results].price
end

function AuctionatorBuyCommodityFrameTemplateMixin:CheckPurchase(newUnitPrice, newTotalPrice)
  local originalUnitPrice = self:GetPrices()

  local prefix = ""
  if originalUnitPrice < newUnitPrice then
    prefix = RED_FONT_COLOR:WrapTextInColorCode("价格已上涨！" .. "\n\n")
  end

  -- 如果是快捷键购买，并且价格低于或等于最大购买价格，则自动确认购买
  if self.isQuickBuy then
    local maxPricesTable = Auctionator.Config.Get(Auctionator.Config.Options.COMMODITY_MAX_PRICES)
    local maxPrice = maxPricesTable[self.expectedItemID]
    
    if maxPrice and newUnitPrice <= maxPrice then
      -- 直接确认购买，不显示对话框
      print(date("%H:%M:%S") .. " 自动确认购买 " .. self.selectedQuantity .. " 个商品，单价: " .. GetMoneyString(newUnitPrice, true))
      C_AuctionHouse.ConfirmCommoditiesPurchase(self.expectedItemID, self.selectedQuantity)
      FrameUtil.UnregisterFrameForEvents(self, PURCHASE_EVENTS)
      self.waitingForPurchase = false
      self.isQuickBuy = false -- 重置标记
      return
    else
      -- 如果价格超过了最大购买价格，取消标记，按正常流程走
      self.isQuickBuy = false
    end
    return
  end

  if Auctionator.Config.Get(Auctionator.Config.Options.SHOPPING_ALWAYS_CONFIRM_COMMODITY_QUANTITY) then
    self.QuantityCheckConfirmationDialog:SetDetails({
      prefix = prefix,
      message = "总计 %s，单价 %s",
      itemID = self.expectedItemID,
      quantity = self.selectedQuantity,
      total = newTotalPrice,
      unitPrice = newUnitPrice,
    })
  else
    self.FinalConfirmationDialog:SetDetails({
      prefix = prefix,
      itemID = self.expectedItemID,
      quantity = self.selectedQuantity,
      total = newTotalPrice,
      unitPrice = newUnitPrice,
    })
  end

  FrameUtil.UnregisterFrameForEvents(self, PURCHASE_EVENTS)
  self.waitingForPurchase = false -- Cancelling is done by dialog after this
end

-- 设置当前商品价格为最大购买价格
function AuctionatorBuyCommodityFrameTemplateMixin:SetCurrentAsMaxPrice()
  if not self.results or not self.expectedItemID then
    return
  end
  
  local unitPrice, _ = self:GetPrices()
  
  if unitPrice and unitPrice > 0 then
    local maxPricesTable = Auctionator.Config.Get(Auctionator.Config.Options.COMMODITY_MAX_PRICES) or {}
    maxPricesTable[self.expectedItemID] = unitPrice
    Auctionator.Config.Set(Auctionator.Config.Options.COMMODITY_MAX_PRICES, maxPricesTable)
    
    -- 更新界面显示
    self:UpdateView()
    
    -- 显示设置成功消息:id+采购价
    print(date("%H:%M:%S") .. " 已设置|cff00ff00 [" .. self.expectedItemID .. "] |r采购价为: " .. GetMoneyString(unitPrice, true))
  end
end

-- 设置手动输入的最大购买价格
function AuctionatorBuyCommodityFrameTemplateMixin:SetManualMaxPrice()
  if not self.expectedItemID then
    return
  end
  
  local goldText = self.DetailsContainer.MaxPriceGold:GetText() or "0"
  local silverText = self.DetailsContainer.MaxPriceSilver:GetText() or "0"
  
  local gold = tonumber(goldText) or 0
  local silver = tonumber(silverText) or 0
  
  local manualPrice = gold * 10000 + silver * 100
  
  if manualPrice and manualPrice > 0 then
    local maxPricesTable = Auctionator.Config.Get(Auctionator.Config.Options.COMMODITY_MAX_PRICES) or {}
    maxPricesTable[self.expectedItemID] = manualPrice
    Auctionator.Config.Set(Auctionator.Config.Options.COMMODITY_MAX_PRICES, maxPricesTable)
    
    -- 更新界面显示
    self:UpdateView()
    
    -- 显示设置成功消息:id+采购价
    print(date("%H:%M:%S") .. " 已设置|cff00ff00 [" .. self.expectedItemID .. "] |r采购价为: " .. GetMoneyString(manualPrice, true))
  else
    print(date("%H:%M:%S") .. " |cffff9900请输入有效的价格|r")
  end
end

-- 删除当前商品的最大购买价格设置
function AuctionatorBuyCommodityFrameTemplateMixin:RemoveMaxPrice()
  if not self.expectedItemID then
    return
  end
  
  local maxPricesTable = Auctionator.Config.Get(Auctionator.Config.Options.COMMODITY_MAX_PRICES) or {}
  
  if maxPricesTable[self.expectedItemID] then
    local oldPrice = maxPricesTable[self.expectedItemID]
    maxPricesTable[self.expectedItemID] = nil
    Auctionator.Config.Set(Auctionator.Config.Options.COMMODITY_MAX_PRICES, maxPricesTable)
    
    -- 更新界面显示
    self:UpdateView()
    
    -- 显示删除成功消息
    print(date("%H:%M:%S") .. " |cffff9900已删除 [" .. self.expectedItemID .. "] 的采购价设置|r")
  else
    print(date("%H:%M:%S") .. " |cffff9900当前商品未设置采购价|r")
  end
end
