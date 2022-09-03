local AddressBookModule = MailUtil:NewModule("MUAddressBookModule", "AceEvent-3.0", "AceHook-3.0")

-- UI elements
local addressBookButton
local dropdownMenu
local dropdownButton

-- constants
local MU_ITEMS_PER_SUBMENU = 2
local MU_DROPDOWN_GUILD_VAL = "guild"
local MU_DROPDOWN_FRIEND_VAL = "friend"
local MU_DROPDOWN_GUILD_PART_VAL = "gpart"
local MU_DROPDOWN_FRIEND_PART_VAL = "fpart"

-- vars
local guildiesList = nil
local friendsList = nil

------------- Helpers -------------
function AddressBookModule.SetSendMailName(dropdownbutton, arg1, arg2, checked)
  SendMailNameEditBox:SetText(arg1)
  if SendMailNameEditBox:HasFocus() then SendMailSubjectEditBox:SetFocus() end
  CloseDropDownMenus()
end

function AddressBookModule:GetFriendsList(part)
  if friendsList then
    return AddressBookModule:ExtractListPart(friendsList, part)
  end
  friendsList = {}
  local numFriends = C_FriendList.GetNumFriends()
  for i = 1, numFriends do
    friendsList[i] = C_FriendList.GetFriendInfoByIndex(i).name
  end
  table.sort(friendsList)
  return AddressBookModule:ExtractListPart(friendsList, part)
end

function AddressBookModule:GetGuildiesList(part)
  if guidiesList then
    return AddressBookModule:ExtractListPart(guildiesList, part)
  end
  guildiesList = {}
  local numGuildies = GetNumGuildMembers(true)
  for i = 1, numGuildies do
    local nameAndRealm, rank, rankIndex, level, class, zone, note, officernote, online, status, classFileName, achievementPoints, achievementRank, isMobile, canSoR = GetGuildRosterInfo(i)
    local c = CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[classFileName] or RAID_CLASS_COLORS[classFileName]
    local name = strsplittable("-", nameAndRealm)[1]
    guildiesList[i] = format("%s |cff%.2x%.2x%.2x(%d %s)|r", name, c.r*255, c.g*255, c.b*255, level, class)
  end
  table.sort(guildiesList)
  return AddressBookModule:ExtractListPart(guildiesList, part)
end

function AddressBookModule:ExtractListPart(list, part)
  if not part then
    return list
  end
  local startIndex = part * MU_ITEMS_PER_SUBMENU - (MU_ITEMS_PER_SUBMENU - 1)
  local endIndex = math.min(startIndex+MU_ITEMS_PER_SUBMENU-1, #list)
  local result = {}
  for i = startIndex, endIndex do
    tinsert(result, list[i])
  end
  return result
end


------------- Menu-building Functions -------------
function AddressBookModule.InitMenu(self, level)
  if not level then return end
  local info = {}

  if level == 1 then
    -- TODO: add alts, friends

    -- guild
    wipe(info)
    info.disabled = not IsInGuild()
    info.hasArrow = 1
    info.text = "Guild"
    info.value = MU_DROPDOWN_GUILD_VAL
    UIDropDownMenu_AddButton(info, level)

    -- friends
    wipe(info)
    info.disabled = C_FriendList.GetNumFriends() == 0
    info.hasArrow = 1
    info.text = "Friends"
    info.value = MU_DROPDOWN_FRIEND_VAL
    UIDropDownMenu_AddButton(info, level)

    -- empty row
    wipe(info)
    info.disabled = 1
    info.notCheckable = 1
    UIDropDownMenu_AddButton(info, level)
    info.disabled = nil

    -- close
    wipe(info)
    info.text = CLOSE
    info.func = self.HideMenu
    UIDropDownMenu_AddButton(info, level)
  elseif level == 2 then
    info.notCheckable = 1
    if UIDROPDOWNMENU_MENU_VALUE == MU_DROPDOWN_FRIEND_VAL then
      AddressBookModule:AddSubmenuButtons(AddressBookModule:GetFriendsList(), MU_DROPDOWN_FRIEND_PART_VAL, level)
    elseif UIDROPDOWNMENU_MENU_VALUE == MU_DROPDOWN_GUILD_VAL then
      AddressBookModule:AddSubmenuButtons(AddressBookModule:GetGuildiesList(), MU_DROPDOWN_GUILD_PART_VAL, level)
    end
  elseif level >= 3 then
    info.notCheckable = 1
    if strfind(UIDROPDOWNMENU_MENU_VALUE, MU_DROPDOWN_FRIEND_PART_VAL) then
      local part = tonumber(strmatch(UIDROPDOWNMENU_MENU_VALUE, MU_DROPDOWN_FRIEND_PART_VAL.."(%d+)"))
      AddressBookModule:AddSubSubmenuButtons(AddressBookModule:GetFriendsList(part), level)
    elseif strfind(UIDROPDOWNMENU_MENU_VALUE, MU_DROPDOWN_GUILD_PART_VAL) then
      local part = tonumber(strmatch(UIDROPDOWNMENU_MENU_VALUE, MU_DROPDOWN_FRIEND_PART_VAL.."(%d+)"))
      AddressBookModule:AddSubSubmenuButtons(AddressBookModule:GetGuildiesList(part), level)
    end
  end
end

function AddressBookModule:AddSubSubmenuButtons(list, level)
  for i = 1, #list do
    local name = list[i]
    local info = {}
    info.text = name
    info.func = AddressBookModule.SetSendMailName
    info.arg1 = strmatch(name, "(%a*)%s") or name
    UIDropDownMenu_AddButton(info, level)
  end
end

function AddressBookModule:AddSubmenuButtons(list, value, level)
  local len = #list
  if len == 0 then
    return
  end
  if len <= MU_ITEMS_PER_SUBMENU then
    for i = 1, len do
      local name = list[i]
      local info = {}
      info.text = name
      info.func = AddressBookModule.SetSendMailName
      info.arg1 = name
      UIDropDownMenu_AddButton(info, level)
    end
  else
    -- More than MU_ITEMS_PER_SUBMENU people, split the list into multiple sublists of MU_ITEMS_PER_SUBMENU
    local info = {}
    info.hasArrow = 1
    info.keepShownOnClick = 1
    info.func = self.UncheckHack
    for i = 1, math.ceil(len/MU_ITEMS_PER_SUBMENU) do
      local partialList = AddressBookModule:ExtractListPart(list, i)
      local first = partialList[1]
      local last = partialList[#partialList]
      if #partialList == 1 then
        info.text = ("Part %d: %s.."):format(i, strsub(first, 1, 2))
      else
        info.text = ("Part %d: %s - %s"):format(i, strsub(first, 1, 2), strsub(last, 1, 2))
      end
      info.value = value..i
      UIDropDownMenu_AddButton(info, level)
    end
  end
end

------------- Dropdown Menu Frame -------------
local dropdownMenu = CreateFrame("Frame", "MUAddressDropdown")
dropdownMenu.displayMode = "MENU"
dropdownMenu.levelAdjust = 0
dropdownMenu.UncheckHack = function(button)
  _G[button:GetName().."Check"]:Hide()
  _G[button:GetName().."UnCheck"]:Hide()
end
dropdownMenu.HideMenu = function()
  if UIDROPDOWNMENU_OPEN_MENU == dropdownMenu then
    CloseDropDownMenus()
  end
end
dropdownMenu.initialize = AddressBookModule.InitMenu

------------- General -------------
function AddressBookModule:OnEnable()
  if not addressBookButton then
    addressBookButton = CreateFrame("Button", "MUAddressBookButton", SendMailFrame)
    addressBookButton:SetWidth(25)
    addressBookButton:SetHeight(25)
    addressBookButton:SetPoint("LEFT", SendMailNameEditBox, "RIGHT", -2, 2)
    addressBookButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    addressBookButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Round")
    addressBookButton:SetDisabledTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Disabled")
    addressBookButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
    addressBookButton:SetScript("OnClick", function(self, button, down)
      ToggleDropDownMenu(1, nil, dropdownMenu, self:GetName(), 0, 0)
    end)
    addressBookButton:SetScript("OnHide", dropdownMenu.HideMenu)
  end
  self:RawHook("SendMailFrame_Reset", true)
  self:RegisterEvent("MAIL_SHOW")
end

function AddressBookModule:SendMailFrame_Reset()
  -- called on successful mail send
  local name = strtrim(SendMailNameEditBox:GetText())
  if name == "" then return self.hooks["SendMailFrame_Reset"]() end
  local message = "Sent mail to "..name
  MailUtil:Print("|cff69ccf0"..message.."|r")
  self.hooks["SendMailFrame_Reset"]()
end

function AddressBookModule:MAIL_SHOW()
  self:RegisterEvent("MAIL_CLOSED", "Reset")
  self:RegisterEvent("PLAYER_LEAVING_WORLD", "Reset")
end

function AddressBookModule:Reset(event)
  guidiesList = nil
  friendsList = nil
  self:UnregisterEvent("MAIL_CLOSED")
  self:UnregisterEvent("PLAYER_LEAVING_WORLD")
end

function AddressBookModule:OnChar(editbox, ...)
  -- TODO - autofill friends and guildies
end