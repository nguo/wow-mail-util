-- Heavily borrowed from Postal https://github.com/wow-vanilla-addons/Postal

local OpenBulkModule = MailUtil:NewModule("MUOpenBulkModule", "AceEvent-3.0")

-- constants
local MU_PROCESS_TYPE_ALL = 1
local MU_PROCESS_TYPE_AH_SOLD = 2
local MU_PROCESS_TYPE_AH_BOUGHT = 4
local MU_PROCESS_TYPE_AH_OTHER = 3 -- expired, cancelled, outbid

local MU_PROCESS_DELAY_SECS = 0.3

-- vars
local numUnshownItems
local lastNumAttach, lastNumGold
local totalGoldCollected
local wait
local skipFlag
local currrentProcessType
local invFull

-- UI elements
local openAllButton
local openAHSoldButton
local openAHOtherButton
local openAHBoughtButton

-- Return the type of mail a message subject is
local SubjectPatterns = {
  AHCancelled = gsub(AUCTION_REMOVED_MAIL_SUBJECT, "%%s", ".*"),
  AHExpired = gsub(AUCTION_EXPIRED_MAIL_SUBJECT, "%%s", ".*"),
  AHOutbid = gsub(AUCTION_OUTBID_MAIL_SUBJECT, "%%s", ".*"),
  AHSold = gsub(AUCTION_SOLD_MAIL_SUBJECT, "%%s", ".*"),
  AHWon = gsub(AUCTION_WON_MAIL_SUBJECT, "%%s", ".*"),
}
function OpenBulkModule:GetMailType(msgSubject)
  if msgSubject then
    for k, v in pairs(SubjectPatterns) do
      if msgSubject:find(v) then return k end
    end
  end
  return "NonAHMail"
end

function OpenBulkModule:OnEnable()
  if not openAllButton then
    openAllButton = CreateFrame("Button", "BIOpenAllButton", InboxFrame, "UIPanelButtonTemplate")
    openAllButton:SetWidth(34)
    openAllButton:SetHeight(25)
    openAllButton:SetPoint("CENTER", InboxFrame, "TOP", -98, -399)
    openAllButton:SetText("All")
    openAllButton:SetScript("OnClick", function() OpenBulkModule:OpenAll(MU_PROCESS_TYPE_ALL, false) end)
    openAllButton:SetFrameLevel(openAllButton:GetFrameLevel() + 1)
    MailUtil:AddTooltipText(openAllButton, "All", "Opens all mail")
  end

  if not openAHSoldButton then
    openAHSoldButton = CreateFrame("Button", "BIOpenAllButton", InboxFrame, "UIPanelButtonTemplate")
    openAHSoldButton:SetWidth(40)
    openAHSoldButton:SetHeight(25)
    openAHSoldButton:SetPoint("CENTER", InboxFrame, "TOP", -56, -399)
    openAHSoldButton:SetText("Sold")
    openAHSoldButton:SetScript("OnClick", function() OpenBulkModule:OpenAll(MU_PROCESS_TYPE_AH_SOLD, false) end)
    openAHSoldButton:SetFrameLevel(openAHSoldButton:GetFrameLevel() + 1)
    MailUtil:AddTooltipText(openAHSoldButton, "AH Sold", "Opens sold auction items")
  end

  if not openAHBoughtButton then
    openAHBoughtButton = CreateFrame("Button", "BIOpenAllButton", InboxFrame, "UIPanelButtonTemplate")
    openAHBoughtButton:SetWidth(42)
    openAHBoughtButton:SetHeight(25)
    openAHBoughtButton:SetPoint("CENTER", InboxFrame, "TOP", -10, -399)
    openAHBoughtButton:SetText("Won")
    openAHBoughtButton:SetScript("OnClick", function() OpenBulkModule:OpenAll(MU_PROCESS_TYPE_AH_BOUGHT, false) end)
    openAHBoughtButton:SetFrameLevel(openAHBoughtButton:GetFrameLevel() + 1)
    MailUtil:AddTooltipText(openAHBoughtButton, "AH Won", "Opens won auction items")
  end

  if not openAHOtherButton then
    openAHOtherButton = CreateFrame("Button", "BIOpenAllButton", InboxFrame, "UIPanelButtonTemplate")
    openAHOtherButton:SetWidth(48)
    openAHOtherButton:SetHeight(25)
    openAHOtherButton:SetPoint("CENTER", InboxFrame, "TOP", 38, -399)
    openAHOtherButton:SetText("Other")
    openAHOtherButton:SetScript("OnClick", function() OpenBulkModule:OpenAll(MU_PROCESS_TYPE_AH_OTHER, false) end)
    openAHOtherButton:SetFrameLevel(openAHOtherButton:GetFrameLevel() + 1)
    MailUtil:AddTooltipText(openAHOtherButton, "AH Other", "Opens misc auction items, including expired, outbid, and cancelled")
  end

  self:RegisterEvent("MAIL_SHOW")
  -- For enabling after a disable
  OpenAllMail:Hide() -- hide Blizzard's Open All button
end

function OpenBulkModule:MAIL_SHOW()
  self:RegisterEvent("MAIL_CLOSED", "Reset")
  self:RegisterEvent("PLAYER_LEAVING_WORLD", "Reset")
  CheckInbox()
end

function OpenBulkModule:Reset(event)
  currrentProcessType = nil
  numUnshownItems = 0
  lastNumAttach, lastNumGold = 0
  totalGoldCollected = 0
  wait = false
  skipFlag = false
  invFull = false

  if event == "MAIL_CLOSED" or event == "PLAYER_LEAVING_WORLD" then
    self:UnregisterEvent("MAIL_CLOSED")
    self:UnregisterEvent("PLAYER_LEAVING_WORLD")
  end
end

function OpenBulkModule:OpenAll(processType)
  self:Reset()
  currrentProcessType = processType
  local numShown, totalItems = GetInboxNumItems()
  numUnshownItems = totalItems - numShown
  if numShown == 0 then
    return
  end

  -- TODO: react to error message
  -- self:RegisterEvent("UI_ERROR_MESSAGE")

  self:ProcessMailAtIndex(numShown)
end

function OpenBulkModule:ProcessMailAtIndex(mailIndex)
  if mailIndex <= 0 then
    -- Reached the end of opening all selected mail
    local numItems, totalItems = GetInboxNumItems()
    if numUnshownItems ~= totalItems - numItems then
      -- We will Open All again if the number of unshown items is different
      MailUtil:Print("Mailbox items changed, opening more mail...")
      return self:OpenAll(currentProcessType, true)
    end

    -- TODO: handle case when we need to refresh the inbox? Or let the user manually refresh?

    if skipFlag then MailUtil:Print("Some Messages May Have Been Skipped.") end

    -- We're done!
    if totalGoldCollected > 0 then
      MailUtil:Print("Total Gold Collected: "..MailUtil:GSC(totalGoldCollected))
    end

    return self:Reset()
  end

  local sender, msgSubject, msgMoney, msgCOD, _, msgItem, _, _, msgText, _, isGM = select(3, GetInboxHeaderInfo(mailIndex))
  -- Skip mail if it contains a CoD or if its from a GM
  if (msgCOD and msgCOD > 0) or (isGM) then
    skipFlag = true
    return self:NextMail(mailIndex)
  end

  -- Filter by mail type
  local mailType = OpenBulkModule:GetMailType(msgSubject)
  if currrentProcessType == MU_PROCESS_TYPE_AH_OTHER and mailType ~= "AHExpired" and mailType ~= "AHCancelled" and mailType ~= "AHOutbid" then
    return self:NextMail(mailIndex)
  elseif currrentProcessType == MU_PROCESS_TYPE_AH_SOLD and mailType ~= "AHSold" then
    return self:NextMail(mailIndex)
  elseif currrentProcessType == MU_PROCESS_TYPE_AH_BOUGHT and mailType ~= "AHWon" then
    return self:NextMail(mailIndex)
  end

  -- @xg debug statement
  MailUtil:Print("DEBUG-open "..mailIndex.." "..(msgSubject or ""))

  -- Print money info before fetching
  local _, _, _, goldCount = MailUtil:CountItemsAndMoney()
  if msgMoney > 0 then
    local moneyString = mailType == "AHSold" and " ["..MailUtil:GSC(msgMoney).."] " or ""
    local playerNameString = ""
    if (mailType == "AHSold" or mailType == "AHWon") then
      playerName = select(3,GetInboxInvoiceInfo(mailIndex))
      playerNameString = playerName and ("("..playerName..")") or ""
      MailUtil:Print(msgSubject..moneyString..playerNameString)
    end
  end

  -- open all attachments from mail
  OpenBulkModule:OpenMailAttachments(mailIndex)
end

function OpenBulkModule:NextMail(currentMailIndex)
  wait = false
  self:ProcessMailAtIndex(currentMailIndex - 1)
end

function OpenBulkModule:NumFreeSlots()
  local free = 0
  for bag = 0,NUM_BAG_SLOTS do
    local bagFree,bagFam = GetContainerNumFreeSlots(bag)
    if bagFam == 0 then
      free = free + bagFree
    end
  end
  return free
end

function OpenBulkModule:OpenMailAttachments(mailIndex)
  if mailIndex <= 0 then
    return
  end
  local _, _, _, goldCount, attachCount = MailUtil:CountItemsAndMoney()
  if wait then
    if lastNumGold ~= goldCount or lastNumAttach ~= attachCount then
      wait = false
    else
      C_Timer.After(MU_PROCESS_DELAY_SECS, function() self:OpenMailAttachments(mailIndex) end)
      return
    end
  end

  lastNumGold = goldCount
  lastNumAttach = attachCount


  local msgSubject, msgMoney, _, _, msgItem = select(4, GetInboxHeaderInfo(mailIndex))

  MailUtil:Print("DEBUG-attachment "..mailIndex.." "..(msgSubject or "").." "..(msgItem or ""))

  if msgMoney == 0 and not msgItem then
    self:NextMail(mailIndex)
    return
  end

  -- -- try to get money first
  if msgMoney > 0 then
    totalGoldCollected = totalGoldCollected + msgMoney
    TakeInboxMoney(mailIndex)
    MailUtil:Print("DEBUG-money "..mailIndex.." "..(msgSubject or "").." "..(msgItem or ""))
    wait = true
    C_Timer.After(MU_PROCESS_DELAY_SECS, function() self:OpenMailAttachments(mailIndex) end)
    return
  end

  -- -- now try to get attachments
  if invFull or self:NumFreeSlots() == 0 then
    invFull = true
    MailUtil:Print("Inventory full, skipping attachments")
    self:NextMail(mailIndex)
    return
  end

  AutoLootMailItem(mailIndex)
  MailUtil:Print("DEBUG-loot "..mailIndex.." "..(msgSubject or "").." "..(msgItem or ""))
  wait = true
  C_Timer.After(MU_PROCESS_DELAY_SECS, function() self:OpenMailAttachments(mailIndex) end)
end