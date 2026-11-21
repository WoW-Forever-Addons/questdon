local _, ns = ...
local C_QuestLog = ns.QL or C_QuestLog -- (25.10.2026) Era shims, Core.lua ApiProxy
local C_SuperTrack = ns.ST or C_SuperTrack -- (25.10.2026) Era shims, Core.lua ApiProxy
local L = ns.L
local Kit = LibStub("DonCore-1.0"):Get("Kit", 25) -- (12.11.2026) Kit.ItemButton: the single button and the list's buttons

-- (12.11.2026, Daniel: a button for each quest's usable item beside its row in the quest list; the single button stays
-- as an option, off by default) the defaults here too, for a DonData from before that day
if type(ns.defaults) == "table" and ns.defaults.trackerItemButtons == nil then
  ns.defaults.trackerItemButtons, ns.defaults.questItemButton = true, false
end

BINDING_HEADER_QUESTDON = "Questdon"
_G["BINDING_NAME_CLICK QuestdonItemButton:LeftButton"] = L["Use quest item"]
_G["BINDING_NAME_CLICK QuestdonTargetButton:LeftButton"] = L["Target a quest mob"]
BINDING_NAME_QUESTDON_TOGGLELIST = L["Show or hide the quest list"] -- (25.10.) Tracker.lua QuestdonToggleList

local LAST_BAG = NUM_BAG_SLOTS or 4
local button
local pendingRefresh = false
-- (Questdon review 1) a drag that ends in combat, a /qd reset in combat: done when the fight is over
local pendingStop, pendingReset = false, false

---------------------------------------------------------------------------
-- Find the item to show
---------------------------------------------------------------------------
-- (12.11.2026) One pass over the quest log: the usable item the game names for each open quest, [questID] = itemID,
-- and the quests that have one in the log's order. Kept tables: the single button and the list's buttons read them.
local logItem, logOrder = {}, {}
local function LogItems()
  for k in pairs(logItem) do logItem[k] = nil end
  for i = #logOrder, 1, -1 do logOrder[i] = nil end
  if not (C_QuestLog and GetQuestLogSpecialItemInfo) then return logItem, logOrder end
  -- (16.10.) the kept quest log list (not C_QuestLog.GetInfo each second), in the log's order
  for _, info in ipairs(ns.QuestLogEntries()) do
    local questID = ns.Num(info.questID)
    local i = questID and ns.Num(ns.Value(C_QuestLog.GetLogIndexForQuestID, questID))
    if i and i > 0 then
      -- (1.0) a finished quest (ready for turn-in) needs its item no more, whatever the game's
      -- "show when complete" flag says
      local ok, link = pcall(GetQuestLogSpecialItemInfo, i)
      if ok and link and ns.Usable(link) and not ns.IsQuestComplete(questID) and not ns.IsQuestFailed(questID) then -- (review 1) failed: no use either
        local id = ns.GetItemID(link)
        if id and not logItem[questID] then logItem[questID] = id logOrder[#logOrder + 1] = questID end
      end
    end
  end
  return logItem, logOrder
end

-- Usable item of a quest in the log: the super-tracked quest's, else the first.
local function FromQuestLog()
  if not (C_QuestLog and GetQuestLogSpecialItemInfo) then return end
  local tracked = C_SuperTrack and ns.Num(ns.Value(C_SuperTrack.GetSuperTrackedQuestID))
  -- (Questdon review 3) nothing tracked: the quest the quest list picked
  if not (tracked and tracked > 0) then tracked = ns.Num(ns.trackerFocus) end
  local map, order = LogItems()
  local firstQuest = order[1]
  local first = firstQuest and map[firstQuest]
  if tracked and map[tracked] then return map[tracked], first, tracked, firstQuest end
  return nil, first, nil, firstQuest
end

-- (1.3.5, Daniel 09.10.) An item in the bags that starts a quest (a looted book, a letter): one
-- click (or the key) opens the quest and auto accept takes it.
-- (1.3.5, Daniel 10.10.) Only when the quest can be taken now (level, previous quests; a quest the
-- data does not know cannot be checked and is offered), and not again in this session once its
-- offer was closed without taking it. It comes after the tracked quest's own item.
local declined = {} -- [questID] = true: offer closed without taking it (this session)
local offerShown    -- questID of the quest dialog that is open
local function StarterAllowed(qid)
  if declined[qid] then return false end
  if ns.QuestLogFull and ns.QuestLogFull() then return false end -- (review 1) the click would only say "log full"
  if ns.QuestInData and not ns.QuestInData(qid) then return true end
  return ns.CanTakeQuest(qid) and true or false
end
local function StarterItem()
  if not (C_Container and C_Container.GetContainerItemQuestInfo) then return end
  for bag = 0, LAST_BAG do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local q = C_Container.GetContainerItemQuestInfo(bag, slot)
      local qid = q and ns.Num(q.questID)
      if qid and not ns.True(q.isActive) and not ns.IsQuestDone(qid) and not ns.InQuestLog(qid) and StarterAllowed(qid) then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info and ns.Num(info.itemID) then return info.itemID, qid end
      end
    end
  end
end
ns.StarterItem = StarterItem -- (tests)

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
          local qid = ns.Num(q.questID)
          return info.itemID, qid and ns.InQuestLog(qid) and qid or nil
        end
      end
    end
  end
end

-- 1.15: the tracked quest's own item comes first, also an item from the bags
-- that an open "use it at a place" objective of that quest needs.
-- (1.3.5, Daniel 10.10.) then an item that starts a quest you can take, then the rest.
-- (1.3.8, F4) also the quest the item is for (nil for a starter or when unknown).
local function FindQuestItem()
  local tracked, first, trackedQuest, firstQuest = FromQuestLog()
  if tracked then return tracked, trackedQuest end
  local use = ns.TrackedUseItem and ns.TrackedUseItem()
  if use and C_Item and ns.Value(C_Item.GetItemSpell, use) then
    return use, C_SuperTrack and ns.Num(ns.Value(C_SuperTrack.GetSuperTrackedQuestID)) or nil
  end
  local starter = StarterItem()
  if starter then return starter, nil end
  if first then return first, firstQuest end
  return FromBags()
end
ns.FindQuestItem = FindQuestItem -- (tests)

---------------------------------------------------------------------------
-- (12.11.2026) The usable item of ONE quest, for its button in the quest list: the item the game names for the quest,
-- else an item in the bags an open "use it at a place" objective needs (DonData), else a usable quest item in the bags
-- the game ties to that quest. Worked out once per change of log or bags (listStale), not with every look at the rows.
---------------------------------------------------------------------------
local listItem, listStale = {}, true -- [questID] = itemID or false
local bagQuestItem = {}              -- [questID] = itemID: usable quest items in the bags by their quest
local starterID, starterQuest
local function ListFresh()
  if not listStale then return end
  listStale = false
  for k in pairs(listItem) do listItem[k] = nil end
  for k in pairs(bagQuestItem) do bagQuestItem[k] = nil end
  LogItems()
  if C_Container and C_Container.GetContainerItemQuestInfo then
    for bag = 0, LAST_BAG do
      for slot = 1, C_Container.GetContainerNumSlots(bag) do
        local q = C_Container.GetContainerItemQuestInfo(bag, slot)
        local qid = q and ns.Num(q.questID)
        if qid and not bagQuestItem[qid] and ns.InQuestLog(qid) then
          local info = C_Container.GetContainerItemInfo(bag, slot)
          local id = info and ns.Num(info.itemID)
          if id and C_Item and ns.Value(C_Item.GetItemSpell, id) then bagQuestItem[qid] = id end
        end
      end
    end
  end
  starterID, starterQuest = StarterItem()
end
function ns.QuestListItem(questID)
  questID = ns.Num(questID)
  if not questID then return nil end
  ListFresh()
  local id = listItem[questID]
  if id == nil then
    id = logItem[questID]
    if not id and not ns.IsQuestComplete(questID) and not ns.IsQuestFailed(questID) then
      local use = ns.QuestUseItem and ns.QuestUseItem(questID)
      if use and C_Item and ns.Value(C_Item.GetItemSpell, use) then id = use else id = bagQuestItem[questID] end
    end
    listItem[questID] = id or false
  end
  return id or nil
end
function ns.ListItemsStale() listStale = true end
-- the item in the bags that starts a quest you can take (the list gives it a row of its own)
function ns.ListStarterItem()
  ListFresh()
  return starterID, starterQuest
end

-- The quest dialog closed: was the quest taken? If not, its starter item leaves the button.
ns.On("QUEST_DETAIL", function()
  local id = ns.Num(ns.Value(GetQuestID))
  offerShown = id and id > 0 and id or nil
end)
ns.On("QUEST_ACCEPTED", function() offerShown = nil end)
ns.On("QUEST_FINISHED", function()
  local id = offerShown
  offerShown = nil
  if not id then return end
  ns.After(1, function()
    -- (Questdon review 3) not when the full log refused it: the starter comes back once a slot is free
    if not ns.InQuestLog(id) and not ns.IsQuestDone(id) and not ns.QuestLogFull() then
      declined[id] = true
      listStale = true
      ns.QueueRefresh("itembutton")
    end
  end)
end)
function ns.StarterDeclined(questID) return declined[questID] == true end -- (tests)

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

-- every item button of ours: the single one and the list's (BAG_UPDATE_COOLDOWN)
local pool, used = {}, 0
local function UpdateCooldown()
  if button then button:UpdateCooldown() end
  for i = 1, used do pool[i]:UpdateCooldown() end
end

-- Blizzard's item tooltip, then the family hint lines last (the single button and the list's buttons)
local function ButtonTooltip(self, clickHint)
  if not self.itemID then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetItemByID(self.itemID)
  local h = ns.Style.COLORS.textHint
  if self.waiting then GameTooltip:AddLine(L["The button changes once the fight is over."], h[1], h[2], h[3], true) end
  if self.far then GameTooltip:AddLine(L["Far from where it is used."], h[1], h[2], h[3], true) end
  GameTooltip:AddLine(clickHint, h[1], h[2], h[3], true)
  GameTooltip:Show()
end

local function CreateButton()
  -- (12.11.2026) DonCore's Kit.ItemButton (icon, count, cooldown, watch); the frame is ours:
  -- (1.19) family frame: dark flat backing one step outside the icon and a 1 px line, instead of the old action slot ring
  button = Kit.ItemButton("QuestdonItemButton", UIParent, { size = 36, frame = false })
  button:SetMovable(true)
  button:SetClampedToScreen(true)
  button:RegisterForDrag("LeftButton")
  button:Hide()
  button.plate = ns.Look.Plate(button, 2)
  button.plate:SetAlpha(ns.Style.DEFAULT_ALPHA)
  button.border = button.plate.border[1]

  button:SetScript("OnDragStart", function(self)
    if IsShiftKeyDown() and not InCombatLockdown() then self:StartMoving() end
  end)
  button:SetScript("OnDragStop", function(self)
    if InCombatLockdown() then pendingStop = true return end
    self:StopMovingOrSizing()
    SavePosition()
  end)
  button:SetScript("OnEnter", function(self) ButtonTooltip(self, L["Click: use. Shift-drag to move."]) end)
  button:SetScript("OnLeave", function(self) ns.Style.HideTooltip(self) end)

  ApplyPosition()
end

-- (1.3.8, F4) Charges count too (an item with 5 uses shows 5), like the game's own buttons.
-- (21.11.2026, Ruckler) kept until the bags change, at most a second (the list's buttons ask five times a second); read
-- directly outside a protected call (tests)
local usesOf, usesAt = {}, nil
ns.On("BAG_UPDATE_DELAYED", function() wipe(usesOf) end)
ns.On("BAG_UPDATE", function() wipe(usesOf) end)
local ReadUses
local function ItemUses(itemID)
  if not (itemID and ns.InScope and ns.InScope()) then return ReadUses(itemID) end
  local now = ns.Num(ns.Value(GetTime)) or 0
  if not usesAt or now - usesAt < 0 or now - usesAt >= 1 then wipe(usesOf) usesAt = now end
  local n = usesOf[itemID]
  if n == nil then n = ReadUses(itemID) or false usesOf[itemID] = n end
  return n or nil
end
function ReadUses(itemID)
  local n = ns.Num(ns.Value(C_Item.GetItemCount, itemID, false, true))
  local stack = ns.Num(ns.Value(C_Item.GetItemCount, itemID))
  if stack and (not n or stack > n) then n = stack end
  return n
end
local function ShowCount(itemID)
  button:SetCount(ReadUses(itemID)) -- (21.11.2026) on its events only: read as it is
end

-- (1.3.8, F4) Far from where the item is used (the item's quest's nearest known spot): the icon is dimmed. Unknown
-- places and other zones leave it as it is.
local FAR_YARDS = 150
local function LookOf(b)
  if not (b and b.itemID and b:IsShown()) then return end
  local far = false
  if b.questID and ns.QuestNearestPoint then
    -- (21.11.2026, Ruckler) the quest list measured it this second already (the same nearest point)
    local known, dist = false, nil
    if ns.TrackerQuestDistance then known, dist = ns.TrackerQuestDistance(b.questID) end
    if not known then dist = select(2, ns.QuestNearestPoint(b.questID)) end
    far = type(dist) == "number" and dist > FAR_YARDS
  end
  b:SetFar(far)
end
local function UpdateLook()
  LookOf(button)
  for i = 1, used do LookOf(pool[i]) end
end
ns.UpdateItemButtonLook = UpdateLook -- (tests)

local function SetWaiting(on) button:SetWaiting(on) end

---------------------------------------------------------------------------
-- (12.11.2026, Daniel: "Die nutzbaren items je quest daneben finde ich auch praktischer als bei uns nur das eine
-- symbol") The buttons in the quest list: one beside each shown quest that has a usable item (the picked quest's card,
-- the row of an item that starts a quest, the quest rows of every tab and look), outside the window's left edge (its
-- right edge when there is no room on the left).
-- Protected buttons may not be made, moved, shown or hidden in a fight, and a frame one of them is anchored to may not
-- move either. So: a pool on UIParent, each button set by screen coordinates (never anchored to a row), and only out of
-- combat. In a fight the buttons stay as they were; one whose row moved or went shows the small watch, and all are put
-- right when the fight is over. The quest list keeps its order in a fight for that (Tracker.lua).
-- ns.TrackerItemSpots(fn) names the rows: fn(questID, itemID, x, y, point); returns the buttons' scale and alpha.
---------------------------------------------------------------------------
local LIST_SIZE = 26
ns.LIST_ITEM_SIZE = LIST_SIZE
local spots, spotN = {}, 0 -- [i] = { itemID, questID, x, y, point }
local listPending = false
local function AddSpot(questID, itemID, x, y, point)
  local id = itemID or ns.QuestListItem(questID)
  if not id then return false end
  -- one button for an item: two quests that share one (or the card and a row) keep the first
  for i = 1, spotN do if spots[i][1] == id then return false end end
  spotN = spotN + 1
  local s = spots[spotN]
  if not s then s = {} spots[spotN] = s end
  s[1], s[2], s[3], s[4], s[5] = id, questID, x, y, point
  return true
end
local function PoolButton(i)
  local b = pool[i]
  if b then return b end
  b = Kit.ItemButton("QuestdonListItem" .. i, UIParent, { size = LIST_SIZE })
  b:Hide()
  b:SetScript("OnEnter", function(self) ButtonTooltip(self, L["Click: use."]) end)
  b:SetScript("OnLeave", function(self) ns.Style.HideTooltip(self) end)
  pool[i] = b
  return b
end
local function SamePlace(b, s)
  return b.spotPoint == s[5] and math.abs((b.spotX or 0) - s[3]) < 1 and math.abs((b.spotY or 0) - s[4]) < 1
end
-- (21.11.2026, Ruckler) count and alpha only when they changed (five times a second for every button)
local function SetCountAlpha(b, n, alpha)
  if b.shownCount ~= n or b.shownItem ~= b.itemID then b.shownCount, b.shownItem = n, b.itemID b:SetCount(n) end
  if alpha and b.shownAlpha ~= alpha then b.shownAlpha = alpha b:SetAlpha(alpha) end
end
local function SyncList()
  if not (Kit and Kit.ItemButton) then return end
  spotN = 0
  local scale, alpha
  if ns.TrackerItemSpots and ns.Active("trackerItemButtons") then scale, alpha = ns.TrackerItemSpots(AddSpot) end
  if InCombatLockdown() then
    -- the watch on every button whose item or place is no longer what the list shows; counts stay true
    local off = spotN ~= used
    for i = 1, used do
      local b, match = pool[i], false
      for j = 1, spotN do
        if spots[j][1] == b.itemID and SamePlace(b, spots[j]) then match = true break end
      end
      b:SetWaiting(not match)
      if not match then off = true end
      SetCountAlpha(b, ItemUses(b.itemID), alpha)
    end
    listPending = off
    return
  end
  listPending = false
  for i = 1, spotN do
    local s, b = spots[i], PoolButton(i)
    if b.itemID ~= s[1] then b:SetItem(s[1]) end
    b.questID = s[2]
    if not SamePlace(b, s) or b.spotScale ~= scale then
      b.spotX, b.spotY, b.spotPoint, b.spotScale = s[3], s[4], s[5], scale
      b:SetScale(scale or 1)
      b:ClearAllPoints()
      b:SetPoint(s[5], UIParent, "BOTTOMLEFT", s[3], s[4])
    end
    b:SetWaiting(false)
    SetCountAlpha(b, ItemUses(s[1]), alpha)
    if not b:IsShown() then b:Show() LookOf(b) end
  end
  for i = spotN + 1, used do
    local b = pool[i]
    b:SetItem(nil)
    b.questID, b.spotX, b.spotY, b.spotPoint = nil, nil, nil, nil
    b:SetWaiting(false)
    b:Hide()
  end
  used = spotN
end
ns.SyncListItems = SyncList
function ns.ListItemButtons() return pool, used, listPending end -- (tests, /qd diag)

local function Refresh()
  if not button then return end
  -- (21.11.2026, Ruckler) the list's items are marked stale by their own events below (ListStale), not by every refresh
  -- (12.11.2026) with the buttons in the quest list the single button is off by default; it keeps its item all the
  -- same, hidden, so its key binding (CLICK QuestdonItemButton) goes on working
  local shown = ns.Active("questItemButton")
  local keyOn = shown or ns.Active("trackerItemButtons")
  if InCombatLockdown() then
    pendingRefresh = true
    -- textures and text may change in combat, the secure attributes not: mark a coming change, keep the count true
    if button.itemID then
      local want = keyOn and FindQuestItem() or nil
      SetWaiting(want ~= button.itemID or (button:IsShown() and not shown)) -- another item, none, or the button goes
      ShowCount(button.itemID)
    end
    SyncList()
    return
  end
  pendingRefresh = false
  SetWaiting(false)

  local itemID, questID = nil, nil
  if keyOn then itemID, questID = FindQuestItem() end
  if not itemID then
    button.questID = nil
    button:SetItem(nil)
    button:Hide()
    SyncList()
    return
  end

  button.questID = questID
  button:SetScale(ns.db.itemButtonScale or 1)
  button:SetItem(itemID)
  ShowCount(itemID)
  if shown then button:Show() else button:Hide() end
  button.far = nil
  UpdateLook()
  SyncList()
  -- (1.3.5) the button shows a quest starter for the first time: the small notice above it
  if ns.db.starterNotice ~= false and ns.StarterNotice then
    local starter, questID = StarterItem()
    if starter == itemID then ns.StarterNotice(starter, questID) end
  end
end

---------------------------------------------------------------------------
-- (1.3.5, Daniel 10.10.: "a small notice in the form of Questdon's quest book: a nice frame above the quest
-- item button, not too big, discreet but still eye-catching") A looted item that starts a quest (the
-- Nibbled-On Book) gets a small note the first time it is on the button this session: its icon and name,
-- "Starts a quest: <quest>", how to open it. Own frame in the quest book's colours (navy, gold lines, the
-- book's corners), above the button (or under the game's messages at the top when the button is not
-- shown). It fades in with the gold rim pulsing for PULSE seconds, stays SHOW seconds and fades out; it
-- goes at once when the quest dialog opens or the quest is taken, when the item leaves the bags, or on a
-- click (the click only closes it: using the item needs the secure button). Never in combat or during a
-- loading screen: it waits. A quiet sound with the option "Sound when done", a chat line too.
---------------------------------------------------------------------------
local NOTICE_W, NOTICE_PAD, ICON_SIZE = 300, 10, 28
local FADE_IN, PULSE, SHOW, FADE_OUT = 0.25, 1.5, 8, 0.6
local NOTICE_SOUND = { "IG_QUEST_LIST_OPEN", "IG_MAINMENU_OPTION_CHECKBOX_ON" }
local MEDIA = "Interface\\AddOns\\Questdon\\Media\\"
local WHITE = "Interface\\Buttons\\WHITE8x8"
local notice
local noticed = {}      -- [itemID] = true: shown this session
local pendingNotice     -- { itemID, questID } waiting for the end of combat or a loading screen
local loading = false
local noticeStats = { shown = 0, sounds = 0, waited = 0 }
function ns.StarterNoticeStats() return noticeStats end

local function Tinted(tex, c, a)
  tex:SetTexture(WHITE)
  tex:SetVertexColor(c[1], c[2], c[3], a or 1)
  return tex
end

local function CreateNotice()
  local B = ns.Style.BOOK
  local f = CreateFrame("Button", "QuestdonStarterNotice", UIParent)
  f:SetSize(NOTICE_W, 70)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  f:Hide()
  -- navy at the top to violet at the bottom, like the quest book
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetTexture(WHITE)
  f.bg:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
  f.bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
  if f.bg.SetGradient and CreateColor then
    pcall(f.bg.SetGradient, f.bg, "VERTICAL", CreateColor(B.backgroundLow[1], B.backgroundLow[2], B.backgroundLow[3], 0.96),
      CreateColor(B.background[1], B.background[2], B.background[3], 0.96))
  else
    f.bg:SetVertexColor(B.background[1], B.background[2], B.background[3], 0.96)
  end
  -- the rim: a gold line outside, a dark and a faint gold line inside (the pulse lights the outer one)
  f.rim = CreateFrame("Frame", nil, f)
  f.rim:SetAllPoints(f)
  local lines = {}
  for _, e in ipairs({ { 0, B.gold, 0.95, true }, { 2, B.goldDark, 0.9 }, { 4, B.gold, 0.35 } }) do
    local inset, col, a, outer = e[1], e[2], e[3], e[4]
    for i = 1, 4 do
      local t = Tinted((outer and f.rim or f):CreateTexture(nil, "BORDER"), col, a)
      if i == 1 then t:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -inset) t:SetPoint("TOPRIGHT", f, "TOPRIGHT", -inset, -inset) t:SetHeight(1)
      elseif i == 2 then t:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inset, inset) t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset) t:SetHeight(1)
      elseif i == 3 then t:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -inset) t:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inset, inset) t:SetWidth(1)
      else t:SetPoint("TOPRIGHT", f, "TOPRIGHT", -inset, -inset) t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset) t:SetWidth(1) end
      lines[#lines + 1] = t
    end
  end
  -- a soft gold glow around the frame while it pulses (our own glow art)
  f.glow = f.rim:CreateTexture(nil, "BACKGROUND")
  f.glow:SetTexture(MEDIA .. "ArrowSealGlow")
  f.glow:SetPoint("TOPLEFT", f, "TOPLEFT", -14, 14)
  f.glow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 14, -14)
  if f.glow.SetBlendMode then pcall(f.glow.SetBlendMode, f.glow, "ADD") end
  f.glow:SetVertexColor(B.gold[1], B.gold[2], B.gold[3], 1)
  f.glow:SetAlpha(0)
  -- the book's corner ornaments, small
  f.corners = {}
  for i, c in ipairs({ { "TOPLEFT", 0, 1, 0, 1 }, { "TOPRIGHT", 1, 0, 0, 1 }, { "BOTTOMLEFT", 0, 1, 1, 0 }, { "BOTTOMRIGHT", 1, 0, 1, 0 } }) do
    local t = f.rim:CreateTexture(nil, "OVERLAY")
    t:SetSize(16, 16)
    if t:SetTexture(MEDIA .. "BookCorner") == false then t:Hide() end
    if t.SetTexCoord then t:SetTexCoord(c[2], c[3], c[4], c[5]) end
    t:SetPoint(c[1], f, c[1], c[1]:find("LEFT") and -2 or 2, c[1]:find("TOP") and 2 or -2)
    f.corners[i] = t
  end
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(ICON_SIZE, ICON_SIZE)
  f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", NOTICE_PAD + 2, -NOTICE_PAD - 2)
  if f.icon.SetTexCoord then f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
  local textX = NOTICE_PAD + 2 + ICON_SIZE + 8
  f.textW = NOTICE_W - textX - NOTICE_PAD - 4
  local function Line(size, color, y)
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local obj, ok, path = _G.GameFontHighlightSmall, false, nil
    if type(obj) == "table" and type(obj.GetFont) == "function" then ok, path = pcall(obj.GetFont, obj) end
    if fs.SetFont and ok and type(path) == "string" then pcall(fs.SetFont, fs, path, size, "") end
    fs:SetTextColor(color[1], color[2], color[3], 1)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", textX, y)
    fs:SetWidth(f.textW)
    return fs
  end
  f.name = Line(13, B.goldLight, -NOTICE_PAD - 1)
  f.quest = Line(12, B.textPrimary, -NOTICE_PAD - 19)
  f.hint = Line(11, B.textHint, -NOTICE_PAD - 37)
  f:SetHeight(NOTICE_PAD * 2 + 50)
  f:SetScript("OnClick", function(self) ns.HideStarterNotice("click") end) -- closes only; the item needs the secure button
  -- one clock for fade in, pulse, stay and fade out; runs only while the notice is shown
  f:SetScript("OnUpdate", function(self, dt)
    self.t = (self.t or 0) + (tonumber(dt) or 0)
    local t = self.t
    if t < FADE_IN then self:SetAlpha(t / FADE_IN) else self:SetAlpha(1) end
    if t < PULSE then
      self.glow:SetAlpha(0.35 + 0.35 * math.sin(t / PULSE * math.pi * 3) ^ 2)
    elseif self.glowOn then
      self.glowOn = false
      self.glow:SetAlpha(0)
    end
    if t >= FADE_IN + SHOW then
      local out = (t - FADE_IN - SHOW) / FADE_OUT
      if out >= 1 then ns.HideStarterNotice("time") return end
      self:SetAlpha(1 - out)
    end
  end)
  notice = f
  return f
end

-- Where it goes: right above the quest item button (wherever it was moved), else under the game's
-- messages at the top of the screen.
local function PlaceNotice(f)
  f:ClearAllPoints()
  if button and button:IsShown() then
    f:SetPoint("BOTTOM", button, "TOP", 0, 8)
    f.anchor = "button"
  else
    f:SetPoint("TOP", UIParent, "TOP", 0, -190)
    f.anchor = "top"
  end
end

local function ItemText(itemID)
  local name, _, quality = ns.GetItemInfo(itemID)
  if type(name) ~= "string" or name == "" then name = ns.ItemName(itemID) end
  local c = type(ITEM_QUALITY_COLORS) == "table" and ITEM_QUALITY_COLORS[ns.Num(quality) or 1]
  local hex = type(c) == "table" and type(c.hex) == "string" and c.hex or nil
  if hex then return hex .. name .. "|r", name end
  return name, name
end

local function QuestName(questID)
  local title = questID and ns.Value(C_QuestLog.GetTitleForQuestID, questID)
  if type(title) == "string" and title ~= "" then return title end
  return questID and ns.DataQuestName and ns.DataQuestName(questID) or nil
end

local function HintText()
  local key = type(GetBindingKey) == "function" and ns.Value(GetBindingKey, "CLICK QuestdonItemButton:LeftButton")
  if type(key) == "string" and key ~= "" then
    local text = type(GetBindingText) == "function" and ns.Value(GetBindingText, key) or key
    return L["Click the quest button or press %s"]:format(type(text) == "string" and text or key)
  end
  return L["Click the quest button"]
end

local function Show(itemID, questID)
  local f = notice or CreateNotice()
  local colored = ItemText(itemID)
  local title = QuestName(questID)
  f.itemID, f.questID = itemID, questID
  f.icon:SetTexture(C_Item and C_Item.GetItemIconByID and ns.Value(C_Item.GetItemIconByID, itemID) or 134400)
  f.name:SetText(colored)
  f.quest:SetText(title and L["Starts a quest: %s"]:format(title) or L["Starts a quest"])
  f.hint:SetText(HintText())
  -- long names: a little smaller, then cut with "..." (never wider than the note)
  for _, fs in ipairs({ f.name, f.quest, f.hint }) do ns.Style.FitText(fs, f.textW) end
  PlaceNotice(f)
  f.t, f.glowOn = 0, true
  f:SetAlpha(0)
  f.glow:SetAlpha(0.35)
  f:Show()
  noticed[itemID] = true
  noticeStats.shown = noticeStats.shown + 1
  if ns.db.notifySound ~= false and PlaySound and SOUNDKIT then
    for _, k in ipairs(NOTICE_SOUND) do
      if SOUNDKIT[k] then pcall(PlaySound, SOUNDKIT[k]) noticeStats.sounds = noticeStats.sounds + 1 break end
    end
  end
  ns.Print(title and L["%s starts a quest: %s"]:format(colored, title) or L["%s starts a quest."]:format(colored))
end

-- The button shows a quest starter (Refresh): the note, once per item and session; in combat or during
-- a loading screen it waits.
function ns.StarterNotice(itemID, questID)
  if not itemID or noticed[itemID] or ns.db.starterNotice == false then return false end
  if loading or ns.True(ns.Value(InCombatLockdown)) then
    if not (pendingNotice and pendingNotice[1] == itemID) then noticeStats.waited = noticeStats.waited + 1 end
    pendingNotice = { itemID, questID }
    return false
  end
  pendingNotice = nil
  Show(itemID, questID)
  return true
end

function ns.HideStarterNotice(reason)
  pendingNotice = nil
  if notice and notice:IsShown() then
    notice:Hide()
    noticeStats.lastHidden = reason
    return true
  end
  return false
end
function ns.StarterNoticeFrame() return notice end -- (tests)
function ns.ResetStarterNotices() noticed, pendingNotice = {}, nil end -- (tests)

local function ShowPending()
  if not pendingNotice or loading or ns.True(ns.Value(InCombatLockdown)) then return end
  local p = pendingNotice
  pendingNotice = nil
  -- still in the bags and still a starter?
  if (ns.Num(ns.Value(C_Item and C_Item.GetItemCount, p[1])) or 0) > 0 then ns.StarterNotice(p[1], p[2]) end
end
ns.On("PLAYER_REGEN_ENABLED", function() ns.After(0.5, ShowPending) end)
ns.On("LOADING_SCREEN_ENABLED", function() loading = true end)
ns.On("LOADING_SCREEN_DISABLED", function() loading = false ns.After(1, ShowPending) end)
-- the quest dialog opens or the quest is taken: the note has done its job
ns.On("QUEST_DETAIL", function() ns.HideStarterNotice("dialog") end)
ns.On("QUEST_ACCEPTED", function() ns.HideStarterNotice("accepted") end)
-- the item left the bags (used, sold, destroyed)
ns.On("BAG_UPDATE_DELAYED", function()
  local id = notice and notice:IsShown() and notice.itemID or (pendingNotice and pendingNotice[1])
  if id and (ns.Num(ns.Value(C_Item and C_Item.GetItemCount, id)) or 0) == 0 then ns.HideStarterNotice("gone") end
end)

-- Many events fire in bursts: bundle them into one refresh. (1.23) Batched
-- with the quest displays (Core.lua): the quest log is read once.
ns.RegisterRefresh("itembutton", Refresh)
local function QueueRefresh() ns.QueueRefresh("itembutton") end
local function QueueRefreshAll() listStale = true ns.QueueRefresh("itembutton") end
ns.RefreshItemButton = QueueRefreshAll

function ns.ResetButtonPosition()
  ns.db.buttonPos = nil
  if button and not InCombatLockdown() then ApplyPosition() elseif button then pendingReset = true end
  if ns.ResetTargetButtonPosition then ns.ResetTargetButtonPosition() end -- (review 1) the target button with it
  ns.Print(L["Button position reset."])
end

ns.OnInit(function()
  CreateButton()
  ns.NewTicker(1, UpdateLook)
end)
ns.On("PLAYER_ENTERING_WORLD", QueueRefresh)
ns.On("QUEST_LOG_UPDATE", QueueRefresh)
ns.On("BAG_UPDATE_DELAYED", QueueRefresh)
ns.On("SUPER_TRACKING_CHANGED", QueueRefresh)
-- (12.11.2026) the list's items are stale at once, not only when the bundled refresh has run (the quest list may be
-- built before it)
-- (21.11.2026, Ruckler) a quest log event only when the log's state changed (a quest more or less, one complete, an
-- objective done: ns.QuestLogState) or ten seconds after the last time (an item's data the client had not loaded yet):
-- the bags were read again after every kill and loot
local staleAt
local function ListStale() staleAt = ns.Num(ns.Value(GetTime)) or 0 ns.ListItemsStale() end
local stateH, stateN
ns.On("QUEST_LOG_UPDATE", function()
  local h, n
  if ns.QuestLogState then h, n = ns.QuestLogState() end
  local now = ns.Num(ns.Value(GetTime)) or 0
  if h == nil or h ~= stateH or n ~= stateN or not staleAt or now - staleAt < 0 or now - staleAt >= 10 then
    stateH, stateN = h, n
    ListStale()
  end
end)
for _, e in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
    "PLAYER_LEVEL_UP" }) do
  ns.On(e, ListStale)
end
ns.On("BAG_UPDATE_COOLDOWN", UpdateCooldown)
ns.On("PLAYER_REGEN_ENABLED", function()
  if pendingStop and button then pendingStop = false button:StopMovingOrSizing() SavePosition() end
  if pendingReset and button then pendingReset = false ApplyPosition() end
  if pendingRefresh then Refresh() elseif listPending then SyncList() end
end)
