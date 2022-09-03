MailUtil = LibStub("AceAddon-3.0"):NewAddon("MailUtil")

local tooltip

local function _openHelpTooltip(parentFrame, title, text)
  GameTooltip:SetOwner(parentFrame, "ANCHOR_BOTTOMRIGHT")
  GameTooltip:AddLine(title)
  GameTooltip:AddLine("|cFFFFFFFF"..text.."|r")
  GameTooltip:Show()
end

local function _closeHelpTooltip(parentFrame)
  GameTooltip:Hide()
end

function MailUtil:Print(message)
  DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0[MailUtil] |r"..message)
end

function MailUtil:AddTooltipText(frame, title, text)
    frame:SetScript("OnEnter", function() _openHelpTooltip(frame, title, text) end)
    frame:SetScript("OnLeave", _closeHelpTooltip)
end

function MailUtil:CountItemsAndMoney()
  local numitems, totalitems = GetInboxNumItems()
  local numread, cash, attachments = 0, 0, 0
  for i=1,numitems do
    local _, _, _, _, money, _, _, itemCount, wasRead = GetInboxHeaderInfo(i)
    if wasRead then numread = numread + 1 end
    cash = cash + money
    if (itemCount or 0) > 0 then
      for j=1,ATTACHMENTS_MAX_RECEIVE do
        local name, itemID, itemTexture, count, quality, canUse = GetInboxItem(i,j)
        if name then
          attachments = attachments + count
        end
      end
    end
  end
  return numitems, totalitems, numread, cash, attachments
end

function MailUtil:GSC(money)
  if not money then return end
  if money < 100 then
        money = money .. " " .. CreateAtlasMarkup("auctionhouse-icon-coin-copper")
    elseif money < 10000 then
        local copper = money % 100
        money = floor(money / 100) .. " " .. CreateAtlasMarkup("auctionhouse-icon-coin-silver")
        if copper > 0 then
            money = money .. "  " .. copper .. " " .. CreateAtlasMarkup("auctionhouse-icon-coin-copper")
        end
    elseif money < 1000000 then
        local silver = floor((money % 10000) / 100)
        money = floor(money / 100 / 100) .. " " .. CreateAtlasMarkup("auctionhouse-icon-coin-gold")
        if silver > 0 then
            money = money .. "  " .. silver .. " " .. CreateAtlasMarkup("auctionhouse-icon-coin-silver")
        end
    else
        money = FormatLargeNumber(floor(money / 100 / 100)) .. " " .. CreateAtlasMarkup("auctionhouse-icon-coin-gold")
    end
    return money
end