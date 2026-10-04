local _, ns = ...
local L = ns.L

BINDING_HEADER_QUESTDON = "Questdon"
_G["BINDING_NAME_CLICK QuestdonItemButton:LeftButton"] = L["Use quest item"]
_G["BINDING_NAME_CLICK QuestdonTargetButton:LeftButton"] = L["Target a quest mob"]

local LAST_BAG = NUM_BAG_SLOTS or 4
local button
local pendingRefresh = false

---------------------------------------------------------------------------
-- Find the item to show
---------------------------------------------------------------------------
-- Usable item of a quest in the log: the super-tracked quest's, else the first.
local function FromQuestLog()
  if not (C_QuestLog and GetQuestLogSpecialItemInfo) then return end
  local tracked = C_SuperTrack and ns.Num(ns.Value(C_SuperTrack.GetSuperTrackedQuestID))
  local first
  for i = 1, ns.Num(ns.Value(C_QuestLog.GetNumQuestLogEntries)) or 0 do
    local info = ns.Value(C_QuestLog.GetInfo, i)
    local questID = type(info) == "table" and not ns.True(info.isHeader) and ns.Num(info.questID)
    if questID then
      -- (1.0) a finished quest (ready for turn-in) needs its item no more, whatever the game's
      -- "show when complete" flag says
      local ok, link = pcall(GetQuestLogSpecialItemInfo, i)
      if ok and link and ns.Usable(link) and not ns.IsQuestComplete(questID) then
        local id = ns.GetItemID(link)
        if id and questID == tracked then return id, first end
        first = first or id
      end
    end
  end
  return nil, first
end

-- Classic style quests: usable quest items sitting in the bags.
local function FromBags()
  if not (C_Container and C_Container.GetContainerItemQuestInfo) then return end
  for bag = 0, LAST_BAG do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local q = C_Container.GetContainerItemQuestInfo(bag, slot)
      if q and (q.isQuestItem or q.questID) then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info and ns.Num(info.itemID) and C_Item and ns.Value(C_Item.GetItemSpell, info.itemID)
          and not (ns.ItemQuestsFinished and ns.ItemQuestsFinished(info.itemID)) then
          return info.itemID
        end
      end
    end
  end
end

-- 1.15: the tracked quest's own item comes first, also an item from the bags
-- that an open "use it at a place" objective of that quest needs.
local function FindQuestItem()
  local tracked, first = FromQuestLog()
  if tracked then return tracked end
  local use = ns.TrackedUseItem and ns.TrackedUseItem()
  if use and C_Item and ns.Value(C_Item.GetItemSpell, use) then return use end
  return first or FromBags()
end

---------------------------------------------------------------------------
-- Button (secure, so attributes only change out of combat)
---------------------------------------------------------------------------
local function SavePosition()
  local point, _, relPoint, x, y = button:GetPoint(1)
  ns.db.buttonPos = { point, relPoint, x, y }
end

local function ApplyPosition()
  button:ClearAllPoints()
  local p = ns.db.buttonPos
  if p then
    button:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else
    button:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
  end
end

local function UpdateCooldown()
  if not (button and button.itemID) then return end
  local start, duration = C_Container.GetItemCooldown(button.itemID)
  -- SetCooldown accepts secret values, so no arithmetic here.
  if start then button.cooldown:SetCooldown(start, duration) end
end

local function CreateButton()
  button = CreateFrame("Button", "QuestdonItemButton", UIParent, "SecureActionButtonTemplate")
  button:SetSize(36, 36)
  button:SetMovable(true)
  button:SetClampedToScreen(true)
  button:RegisterForClicks("AnyUp", "AnyDown")
  button:RegisterForDrag("LeftButton")
  button:Hide()

  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetAllPoints()
  button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  -- (1.19) family frame: dark flat backing one step outside the icon and a
  -- 1 px line, instead of the old action slot ring
  button.plate = ns.Look.Plate(button, 2)
  button.plate:SetAlpha(ns.Style.DEFAULT_ALPHA)
  button.border = button.plate.border[1]

  button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  button.count:SetPoint("BOTTOMRIGHT", -2, 2)

  button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
  button.cooldown:SetAllPoints()

  button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

  button:SetScript("OnDragStart", function(self)
    if IsShiftKeyDown() and not InCombatLockdown() then self:StartMoving() end
  end)
  button:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition()
  end)
  button:SetScript("OnEnter", function(self)
    if not self.itemID then return end
    -- Blizzard's item tooltip, then the family hint line last
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(self.itemID)
    local h = ns.Style.COLORS.textHint
    GameTooltip:AddLine(L["Click: use. Shift-drag to move."], h[1], h[2], h[3], true)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function(self) ns.Style.HideTooltip(self) end)

  ApplyPosition()
end

local function Refresh()
  if not button then return end
  if InCombatLockdown() then pendingRefresh = true return end
  pendingRefresh = false

  local itemID = ns.Active("questItemButton") and FindQuestItem() or nil
  if not itemID then
    button.itemID = nil
    button:SetAttribute("type", nil)
    button:Hide()
    return
  end

  button.itemID = itemID
  button:SetScale(ns.db.itemButtonScale or 1)
  button:SetAttribute("type", "item")
  button:SetAttribute("item", "item:" .. itemID)
  button.icon:SetTexture(C_Item.GetItemIconByID(itemID))
  local count = ns.Num(ns.Value(C_Item.GetItemCount, itemID))
  button.count:SetText(count and count > 1 and count or "")
  UpdateCooldown()
  button:Show()
end

-- Many events fire in bursts: bundle them into one refresh. (1.23) Batched
-- with the quest displays (Core.lua): the quest log is read once.
ns.RegisterRefresh("itembutton", Refresh)
local function QueueRefresh() ns.QueueRefresh("itembutton") end
ns.RefreshItemButton = QueueRefresh

function ns.ResetButtonPosition()
  ns.db.buttonPos = nil
  if button and not InCombatLockdown() then ApplyPosition() end
  ns.Print(L["Button position reset."])
end

ns.OnInit(CreateButton)
ns.On("PLAYER_ENTERING_WORLD", QueueRefresh)
ns.On("QUEST_LOG_UPDATE", QueueRefresh)
ns.On("BAG_UPDATE_DELAYED", QueueRefresh)
ns.On("SUPER_TRACKING_CHANGED", QueueRefresh)
ns.On("BAG_UPDATE_COOLDOWN", UpdateCooldown)
ns.On("PLAYER_REGEN_ENABLED", function()
  if pendingRefresh then Refresh() end
end)
