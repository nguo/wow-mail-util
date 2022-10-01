-- Heavily borrowed from Postal https://github.com/wow-vanilla-addons/Postal

local OpenBulkModule = MailUtil:NewModule("MUOpenBulkModule", "AceEvent-3.0")

-- constants
local MU_PROCESS_TYPE_ALL = 1
local MU_PROCESS_TYPE_AH_SOLD = 2
local MU_PROCESS_TYPE_AH_BOUGHT = 4
local MU_PROCESS_TYPE_AH_OTHER = 3 -- expired, cancelled, outbid

local MU_PROCESS_DELAY_SECS = 0.3

-- vars
local numUnshownItems = 0
local totalGoldCollected = 0
local skipFlag = false
local currentProcessType = nil
local invFull = false
local firstMailDaysLeft

-- UI elements
local uiOpenAllButton
local uiOpenAHSoldButton
local uiOpenAHOtherButton
local uiOpenAHBoughtButton

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
  if not uiOpenAllButton then
    uiOpenAllButton = CreateFrame("Button", "MUOpenAllButton", InboxFrame, "UIPanelButtonTemplate")
    uiOpenAllButton:SetWidth(34)
    uiOpenAllButton:SetHeight(25)
    uiOpenAllButton:SetPoint("CENTER", InboxFrame, "TOP", -98, -399)
    uiOpenAllButton:SetText("All")
    uiOpenAllButton:SetScript("OnClick", function() OpenBulkModule:OpenAll(MU_PROCESS_TYPE_ALL, false) end)
    uiOpenAllButton:SetFrameLevel(uiOpenAllButton:GetFrameLevel() + 1)
    MailUtil:AddTooltipText(uiOpenAllButton, "All", "Opens all mail")
  end

  if not uiOpenAHSoldButton then
    uiOpenAHSoldButton = CreateFrame("Button", "MUOpenAllButton", InboxFrame, "UIPanelButtonTemplate")
    uiOpenAHSoldButton:SetWidth(40)
    uiOpenAHSoldButton:SetHeight(25)
    uiOpenAHSoldButton:SetPoint("CENTER", InboxFrame, "TOP", -56, -399)
    uiOpenAHSoldButton:SetText("Sold")
    uiOpenAHSoldButton:SetScript("OnClick", function() OpenBulkModule:OpenAll(MU_PROCESS_TYPE_AH_SOLD, false) end)
    uiOpenAHSoldButton:SetFrameLevel(uiOpenAHSoldButton:GetFrameLevel() + 1)
    MailUtil:AddTooltipText(uiOpenAHSoldButton, "AH Sold", "Opens sold auction items")
  end

  if not uiOpenAHBoughtButton then
    uiOpenAHBoughtButton = CreateFrame("Button", "MUOpenAllButton", InboxFrame, "UIPanelButtonTemplate")
    uiOpenAHBoughtButton:SetWidth(42)
    uiOpenAHBoughtButton:SetHeight(25)
    uiOpenAHBoughtButton:SetPoint("CENTER", InboxFrame, "TOP", -10, -399)
    uiOpenAHBoughtButton:SetText("Won")
    uiOpenAHBoughtButton:SetScript("OnClick", function() OpenBulkModule:OpenAll(MU_PROCESS_TYPE_AH_BOUGHT, false) end)
    uiOpenAHBoughtButton:SetFrameLevel(uiOpenAHBoughtButton:GetFrameLevel() + 1)
    MailUtil:AddTooltipText(uiOpenAHBoughtButton, "AH Won", "Opens won auction items")
  end

  if not uiOpenAHOtherButton then
    uiOpenAHOtherButton = CreateFrame("Button", "MUOpenAllButton", InboxFrame, "UIPanelButtonTemplate")
    uiOpenAHOtherButton:SetWidth(48)
    uiOpenAHOtherButton:SetHeight(25)
    uiOpenAHOtherButton:SetPoint("CENTER", InboxFrame, "TOP", 38, -399)
    uiOpenAHOtherButton:SetText("Other")
    uiOpenAHOtherButton:SetScript("OnClick", function() OpenBulkModule:OpenAll(MU_PROCESS_TYPE_AH_OTHER, false) end)
    uiOpenAHOtherButton:SetFrameLevel(uiOpenAHOtherButton:GetFrameLevel() + 1)
    MailUtil:AddTooltipText(uiOpenAHOtherButton, "AH Other", "Opens misc auction items, including expired, outbid, and cancelled")
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
  currentProcessType = nil
  numUnshownItems = 0
  totalGoldCollected = 0
  skipFlag = false
  invFull = false

  if event == "MAIL_CLOSED" or event == "PLAYER_LEAVING_WORLD" then
    self:UnregisterEvent("MAIL_CLOSED")
    self:UnregisterEvent("PLAYER_LEAVING_WORLD")
  end
end

function OpenBulkModule:OpenAll(processType)
  self:Reset()
  currentProcessType = processType
  local numShown, totalItems = GetInboxNumItems()
  numUnshownItems = totalItems - numShown
  if numShown == 0 then
    return
  end

  firstMailDaysLeft = select(7, GetInboxHeaderInfo(1))

  -- TODO: react to error message
  -- self:RegisterEvent("UI_ERROR_MESSAGE")

  self:ProcessMailAtIndex(numShown)
end

function OpenBulkModule:ProcessMailAtIndex(mailIndex)
  local currentFirstMailDaysLeft = select(7, GetInboxHeaderInfo(1))
  if currentFirstMailDaysLeft ~= 0 and currentFirstMailDaysLeft ~= firstMailDaysLeft then
    -- First mail's daysLeft changed, indicating we have a
    -- fresh MAIL_INBOX_UPDATE that has new data from CheckInbox()
    -- so we reopen from the last mail
    MailUtil:Print("Current first has changed, open all again")
    return self:OpenAll(currentProcessType)
  end
  if mailIndex <= 0 then
    -- Reached the end of opening all selected mail
    local numItems, totalItems = GetInboxNumItems()
    if numUnshownItems ~= totalItems - numItems then
      -- We will Open All again if the number of unshown items is different
      MailUtil:Print("Mailbox items changed, opening more mail...")
      return self:OpenAll(currentProcessType)
    elseif totalItems > numItems and numItems < MAX_MAIL_SHOWN then
      MailUtil:Print("We should refresh mail...")
    end

    -- TODO: handle case when we need to refresh the inbox? Or let the user manually refresh?

    if skipFlag then MailUtil:Print("Some Messages May Have Been Skipped.") end

    -- We're done!
    if totalGoldCollected > 0 then
      MailUtil:Print("Total Gold Collected: "..MailUtil:GSC(totalGoldCollected))
    end

    return self:Reset()
  end

  local sender, msgSubject, msgMoneyAmt, msgCOD, _, msgAttachmtAmt, _, _, msgText, _, isGM = select(3, GetInboxHeaderInfo(mailIndex))
  msgMoneyAmt = msgMoneyAmt or 0
  msgAttachmtAmt = msgAttachmtAmt or 0
  -- Skip mail if it contains a CoD or if its from a GM
  if (msgCOD and msgCOD > 0) or (isGM) then
    skipFlag = true
    return self:NextMail(mailIndex)
  end

  -- Filter by mail type
  local mailType = OpenBulkModule:GetMailType(msgSubject)
  if currentProcessType == MU_PROCESS_TYPE_AH_OTHER and mailType ~= "AHExpired" and mailType ~= "AHCancelled" and mailType ~= "AHOutbid" then
    return self:NextMail(mailIndex)
  elseif currentProcessType == MU_PROCESS_TYPE_AH_SOLD and mailType ~= "AHSold" then
    return self:NextMail(mailIndex)
  elseif currentProcessType == MU_PROCESS_TYPE_AH_BOUGHT and mailType ~= "AHWon" then
    return self:NextMail(mailIndex)
  end

  -- Print money info before fetching
  if msgMoneyAmt > 0 then
    local moneyString = mailType == "AHSold" and " ["..MailUtil:GSC(msgMoneyAmt).."] " or ""
    local playerNameString = ""
    if (mailType == "AHSold" or mailType == "AHWon") then
      playerName = select(3,GetInboxInvoiceInfo(mailIndex))
      playerNameString = playerName and ("("..playerName..")") or ""
      MailUtil:Print(msgSubject..moneyString..playerNameString)
    end
  end

  -- construct mail data and open attachments/money for mail
  local finalAttachmtIndex = ATTACHMENTS_MAX_RECEIVE
  while not GetInboxItemLink(mailIndex, finalAttachmtIndex) and finalAttachmtIndex > 0 do
    finalAttachmtIndex = finalAttachmtIndex - 1
  end
  local mailState = {
    index = mailIndex,
    finalAttachmtIndex = finalAttachmtIndex,
    origAttachmtAmt = msgAttachmtAmt or 0,
    origMoneyAmt = msgMoneyAmt or 0,
    wasLastAttachmt = false,
    isTaking = false,
    prevInboxMoneyAmt = 0,
    prevInboxAttachmtAmt = 0
  }
  OpenBulkModule:OpenMailAttachments(mailState)
end

function OpenBulkModule:NextMail(currentMailIndex)
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

function OpenBulkModule:OpenMailAttachments(mailState)
  local mailIndex = mailState.index
  if mailIndex <= 0 then
    return
  end
  -- get total count of items and money from mailbox.
  -- we can't rely on getting the single mail from the mail index because if the mail was completely open before this callback,
  -- it's possible for a previously-skipped mail to take the place of that mail index and we won't be checking against the same mail anymore.
  -- this is why we store information about the last attachment
  local _, _, _, inboxMoneyAmt, inboxAttachmtAmt = MailUtil:CountItemsAndMoney()
  inboxMoneyAmt = inboxMoneyAmt or 0
  inboxAttachmtAmt = inboxAttachmtAmt or 0
  if mailState.isTaking then
    if mailState.prevInboxMoneyAmt ~= inboxMoneyAmt or mailState.prevInboxAttachmtAmt ~= inboxAttachmtAmt then
      -- either money amount has changed - meaning gold was successfully taken,
      -- or attachment amount has changed - meaning previous attachment was taken.
      -- if the previous attachment was the last one, or the mail never had attachments, go to next mail.
      if mailState.origAttachmtAmt == 0 or mailState.wasLastAttach then
        self:NextMail(mailIndex)
        return
      end
      -- otherwise, keep going.
      mailState.isTaking = false
    else
      -- stil waiting for something to change - keep waiting.
      C_Timer.After(MU_PROCESS_DELAY_SECS, function() self:OpenMailAttachments(mailState) end)
      return
    end
  end

  mailState.prevInboxMoneyAmt = inboxMoneyAmt
  mailState.prevInboxAttachmtAmt = inboxAttachmtAmt

  local msgSubject, msgMoneyAmt, _, _, msgAttachmtAmt = select(4, GetInboxHeaderInfo(mailIndex))
  msgMoneyAmt = msgMoneyAmt or 0
  msgAttachmtAmt = msgAttachmtAmt or 0
  
  if msgMoneyAmt == 0 and msgAttachmtAmt == 0 then
    -- nothing else in mail - go to next mail
    self:NextMail(mailIndex)
    return
  end

  -- take money first
  if msgMoneyAmt > 0 then
    totalGoldCollected = totalGoldCollected + msgMoneyAmt
    TakeInboxMoney(mailIndex)
    mailState.isTaking = true
    C_Timer.After(MU_PROCESS_DELAY_SECS, function() self:OpenMailAttachments(mailState) end)
    return
  end

  -- now take attachments if we have space
  if invFull or self:NumFreeSlots() == 0 then
    invFull = true
    self:NextMail(mailIndex)
    return
  end
  -- start taking attachment from the front
  local attachmtIndex = 1
  while not GetInboxItemLink(mailIndex, attachmtIndex) and attachmtIndex <= mailState.finalAttachmtIndex do
    attachmtIndex = attachmtIndex + 1
  end
  if attachmtIndex == mailState.finalAttachmtIndex then
    mailState.wasLastAttach = true
  end
  TakeInboxItem(mailIndex, attachmtIndex)
  mailState.isTaking = true
  C_Timer.After(MU_PROCESS_DELAY_SECS, function() self:OpenMailAttachments(mailState) end)
end