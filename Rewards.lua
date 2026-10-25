local _, ns = ...
local C_TooltipInfo = ns.TT or C_TooltipInfo -- (25.10.2026) Era shims, Core.lua ApiProxy
local L = ns.L

local marker   -- our own frame with a gold coin, placed over the best reward button
local waiting  -- true while item data for the open reward window is loading
local open     -- (1.28) true from QUEST_COMPLETE to QUEST_FINISHED: the reward window is open

-- Find the reward button without calling Blizzard code: only read frames.
-- Forever runs its UI through secure delegates; calling into it can taint it.
local function GetRewardButton(index)
  local rewards = QuestInfoRewardsFrame
  if rewards and type(rewards.RewardButtons) == "table" then
    for _, button in ipairs(rewards.RewardButtons) do
      if button.type == "choice" and button:GetID() == index and button:IsShown() then
        return button
      end
    end
  end
  local button = _G["QuestInfoRewardsFrameQuestInfoItem" .. index]
  if button and button:IsShown() then return button end
end

local function HideMarker()
  if marker then marker:Hide() end
end

local function ShowMarker(button)
  if not button then return end
  if not marker then
    marker = CreateFrame("Frame", "QuestdonRewardMarker", UIParent)
    marker:SetSize(16, 16)
    marker:SetFrameStrata("DIALOG")
    marker.icon = marker:CreateTexture(nil, "OVERLAY")
    marker.icon:SetAllPoints()
    marker.icon:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
  end
  marker:ClearAllPoints()
  marker:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -2)
  marker:Show()
end

-- Returns index, value, link of the most valuable choice, or nil + pending flag.
local function FindBest()
  local bestIndex, bestValue, bestLink = nil, 0, nil
  local pending = false
  for i = 1, ns.Num(ns.Value(GetNumQuestChoices)) or 0 do
    local link = ns.Value(GetQuestItemLink, "choice", i)
    local count = GetQuestItemInfo and select(4, pcall(GetQuestItemInfo, "choice", i))
    count = ns.Num(count)
    local price = type(link) == "string" and ns.GetSellPrice(link) or nil
    if price == nil then
      pending = true
      ns.RequestItem(link and ns.GetItemID(link))
    else
      local value = price * math.max(count or 1, 1)
      if value > bestValue then
        bestIndex, bestValue, bestLink = i, value, link
      end
    end
  end
  return bestIndex, bestValue, bestLink, pending
end

local Suggest -- (1.3.8, below)
local pausedAtOpen = false
local function Evaluate()
  HideMarker()
  if Suggest then pcall(Suggest) end
  -- (1.28) the window may be closed again before the deferred evaluation runs
  -- (QUEST_FINISHED): then nothing is picked, marked or said
  if not open then waiting = false return end
  if (ns.Num(ns.Value(GetNumQuestChoices)) or 0) < 2 then waiting = false return end
  local db = ns.db
  if not (db.highlightBest or db.autoPickBest) then return end

  local index, value, link, pending = FindBest()
  waiting = pending
  if pending then return end -- retried on ITEM_DATA_LOAD_RESULT
  if not index then return end -- all choices worth nothing

  -- (1.3.5) repeatable quests are never turned in automatically (Quests.lua): the marker only
  if db.autoPickBest and ns.Active("autoTurnIn") and not ns.IsPaused() and not pausedAtOpen and not (ns.SkipAutoTurnIn and ns.SkipAutoTurnIn(ns.Value(GetQuestID)))
      and not (ns.QuestCostsGold and ns.QuestCostsGold(ns.Value(GetQuestID))) then -- (Questdon review 1) no gold paid
    ns._rewardAuto = true -- (1.3.8) Questdon chose: not a player's pick
    GetQuestReward(index)
    return
  end
  if db.highlightBest then
    ShowMarker(GetRewardButton(index))
    ns.Print(L["Most valuable reward: %s (%s)"]:format(link, ns.Money(value)))
  end
end

local Snapshot -- (1.3.8, below)
ns.On("QUEST_COMPLETE", function()
  open = true
  ns._rewardAuto = nil
  pausedAtOpen = ns.IsPaused() -- (Questdon review 4) Shift held when the window opened: no pick, also not later
  if Snapshot then pcall(Snapshot) end
  -- Wait one frame so Blizzard has laid out the reward buttons.
  ns.After(0, Evaluate)
end)

ns.On("ITEM_DATA_LOAD_RESULT", function()
  if waiting and QuestFrame and QuestFrame:IsShown() then
    waiting = false
    ns.After(0.1, Evaluate)
  end
end)

local HideGlow -- (1.3.8, below)
ns.On("QUEST_FINISHED", function()
  open = false
  waiting = false
  HideMarker()
  if HideGlow then HideGlow() end
end)

---------------------------------------------------------------------------
-- (1.3.8, Daniel 13.10.: "remember which reward the player picks, so we learn which class prefers which reward
-- and suggest it"; "a green glowing frame as the suggestion; the coin for the highest vendor price stays, small as
-- now"; "until there is enough data, a rule with armor type and the stats useful for the class")
--
-- Remembered: the reward a player picks by hand (not when Questdon picked it), with class and talent tree, in
-- QuestdonDB.rewardPicks; /qd export and the sharing send it as "R quest class tree item". The suggestion: the
-- reward PICKS_NEEDED or more players of your class picked (shipped data ns.LEARNED_REWARDS and what others
-- shared), else the class rule: armor you can wear (the best type for your class and level first), the stats
-- your class uses, only when it beats what you wear in that slot. A green frame marks it.
---------------------------------------------------------------------------
local PICKS_NEEDED = 5
-- the armor a class wears best (classic: plate and mail from level 40)
local ARMOR = { [1] = { 3, 4 }, [2] = { 3, 4 }, [3] = { 2, 3 }, [7] = { 2, 3 }, [4] = { 2, 2 }, [11] = { 2, 2 },
  [5] = { 1, 1 }, [8] = { 1, 1 }, [9] = { 1, 1 } }
-- weapon types a class can use (item subclass IDs of class 2)
local WEAPONS = {
  [1] = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 }, [2] = { 0, 1, 4, 5, 6, 7, 8 },
  [3] = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 }, [4] = { 2, 3, 4, 7, 13, 15, 16, 18 },
  [5] = { 4, 10, 15, 19 }, [7] = { 0, 1, 4, 5, 10, 13, 15 }, [8] = { 7, 10, 15, 19 }, [9] = { 7, 10, 15, 19 },
  [11] = { 4, 5, 10, 13, 15 },
}
-- how much a point of a stat is worth to the class while levelling (strength, agility, stamina, intellect,
-- spirit): the common ground of the levelling and WoW Forever guides of Icy Veins, Warcraft Tavern, Mobalytics
-- and wow.gg (13.10.2026, store/analysis/stat_weights.py has the sources and the method)
local WEIGHTS = {
  [1] = { 2, 1.5, 1.25, 0, 0.5 }, [2] = { 2, 1.25, 0.5, 0.75, 0.5 }, [3] = { 0, 2, 0.5, 1, 1.25 },
  [4] = { 1.5, 2, 0.75, 0, 0.75 }, [5] = { 0, 0, 1, 1.75, 1.5 }, [7] = { 2, 1.5, 0.5, 1, 0.25 },
  [8] = { 0, 0, 1, 2, 1.5 }, [9] = { 0, 0, 1.5, 1.75, 1.25 }, [11] = { 1.75, 1.75, 0.75, 0.25, 0.5 },
}
-- shamans and druids with most talents in a caster tree (elemental, balance, restoration) want intellect and spirit
local CASTER_TREES = { [7] = { [1] = true, [3] = true }, [11] = { [1] = true, [3] = true } }
local CASTER_WEIGHTS = { 0, 0, 0.5, 1.75, 1.25 }
local STAT_KEYS = { "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STAMINA_SHORT",
  "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPIRIT_SHORT" }
local SLOTS = { INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
  INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
  INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
  INVTYPE_WEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_SHIELD = { 17 },
  INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 },
  INVTYPE_THROWN = { 18 } }

local function ClassID()
  if type(UnitClass) ~= "function" then return nil end
  local ok, _, _, id = pcall(UnitClass, "player")
  return ok and ns.Num(id) or nil
end
-- the talent tree with the most points (0 when the game does not say)
local function Tree()
  local best, bestN = 0, 0
  if type(GetTalentTabInfo) ~= "function" then return 0 end
  for i = 1, 3 do
    local ok, _, _, a, _, b = pcall(GetTalentTabInfo, i)
    local n = ok and (ns.Num(a) or ns.Num(b)) or nil
    if n and n > bestN then best, bestN = i, n end
  end
  return best
end
ns.RewardTree = Tree

local function Instant(item)
  local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not fn then return nil end
  local ok, id, _, _, equipLoc, _, classID, subID = pcall(fn, item)
  if not ok then return nil end
  return ns.Num(id), equipLoc, ns.Num(classID), ns.Num(subID)
end
local function Stats(link)
  local fn = (C_Item and C_Item.GetItemStats) or GetItemStats
  if not (fn and type(link) == "string") then return {} end
  local ok, t = pcall(fn, link)
  return ok and type(t) == "table" and t or {}
end
local function Has(list, v) for _, x in ipairs(list or {}) do if x == v then return true end end return false end

-- the class rule: a score for an item, or nil when the class cannot use it
local function Score(link, class, level)
  local id, equipLoc, itemClass, sub = Instant(link)
  if not id or not SLOTS[equipLoc or ""] then return nil end
  local score = 0
  if itemClass == 4 and sub and sub >= 1 and sub <= 4 and equipLoc ~= "INVTYPE_CLOAK" then
    local a = ARMOR[class]
    if not a then return nil end
    local best = (level or 1) >= 40 and a[2] or a[1]
    if sub > best then return nil end
    score = score + (sub == best and 3 or -2)
  elseif itemClass == 4 and sub == 6 then
    if not (class == 1 or class == 2 or class == 7) then return nil end
  elseif itemClass == 2 then
    if not Has(WEAPONS[class], sub) then return nil end
  end
  local w = CASTER_TREES[class] and CASTER_TREES[class][ns.RewardTree()] and CASTER_WEIGHTS or WEIGHTS[class] or {}
  local st = Stats(link)
  for i, key in ipairs(STAT_KEYS) do score = score + (w[i] or 0) * (ns.Num(st[key]) or 0) end
  return score, SLOTS[equipLoc]
end
ns.RewardScore = Score -- (tests)

-- (22.10., Daniel: "early on the suggestion is wrong: without stats it goes almost only by more armor") the armor
-- value of an item: the game's item stats (RESISTANCE0_NAME), else the tooltip line ("%s Armor", ARMOR_TEMPLATE)
local ARMOR_PAT
local function Armor(link)
  if type(link) ~= "string" then return 0 end
  local a = ns.Num(Stats(link).RESISTANCE0_NAME)
  if a and a > 0 then return a end
  local tip = C_TooltipInfo and C_TooltipInfo.GetHyperlink
  if not tip then return 0 end
  if not ARMOR_PAT then
    local t = type(ARMOR_TEMPLATE) == "string" and ARMOR_TEMPLATE or "%s Armor"
    ARMOR_PAT = "^" .. t:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%[sd]", "([%%d%%.,]+)") .. "$"
  end
  local ok, data = pcall(tip, link)
  for _, line in ipairs(ok and type(data) == "table" and data.lines or {}) do
    local txt = line.leftText
    local n = type(txt) == "string" and txt:match(ARMOR_PAT)
    if n then return ns.Num((n:gsub("[,%.]", ""))) or 0 end
  end
  return 0
end
ns.RewardArmor = Armor -- (tests)

-- has the item any of the stats the rule weighs?
local function HasStats(link)
  local st = Stats(link)
  for _, key in ipairs(STAT_KEYS) do if (ns.Num(st[key]) or 0) > 0 then return true end end
  return false
end

local function Worn(slots, class, level)
  local worst
  for _, slot in ipairs(slots) do
    local link = ns.Value(GetInventoryItemLink, "player", slot)
    local s = link and Score(link, class, level) or 0
    if not worst or s < worst then worst = s end -- (rings, trinkets) the weaker one is what a new one replaces
  end
  return worst or 0
end

-- players' picks for this quest and class: { [itemID] = players }
local function Picks(questID, class)
  local out = {}
  local shipped = ns.LEARNED_REWARDS and ns.LEARNED_REWARDS[questID] and ns.LEARNED_REWARDS[questID][class]
  for item, n in pairs(type(shipped) == "table" and shipped or {}) do out[item] = (out[item] or 0) + (ns.Num(n) or 0) end
  if ns.SharedRewardPicks then
    for item, n in pairs(ns.SharedRewardPicks(questID, class) or {}) do out[item] = (out[item] or 0) + n end
  end
  return out
end

-- index of the suggested choice and why ("players" or "rule"), nil when there is none
function ns.SuggestRewardIndex()
  local n = ns.Num(ns.Value(GetNumQuestChoices)) or 0
  if n < 2 then return nil end
  local class, level = ClassID(), ns.PlayerLevel and ns.PlayerLevel() or 1
  if not class then return nil end
  local q = ns.Num(ns.Value(GetQuestID))
  local picks = q and Picks(q, class) or {}
  local bestI, bestN = nil, 0
  for i = 1, n do
    local id = ns.GetItemID(ns.Value(GetQuestItemLink, "choice", i))
    local c = id and picks[id] or 0
    if c > bestN then bestI, bestN = i, c end
  end
  if bestI and bestN >= PICKS_NEEDED then return bestI, "players" end
  -- (22.10.) no choice has stats: the armor you can wear that adds the most armor to what you wear in its slot
  local anyStats = false
  for i = 1, n do
    local link = ns.Value(GetQuestItemLink, "choice", i)
    if link and HasStats(link) then anyStats = true break end
  end
  if not anyStats then
    local armI, armGain
    for i = 1, n do
      local link = ns.Value(GetQuestItemLink, "choice", i)
      local s, slots = Score(link, class, level)
      local new = s and Armor(link) or 0
      if new > 0 then
        local worn
        for _, slot in ipairs(slots) do
          local wl = ns.Value(GetInventoryItemLink, "player", slot)
          local w = wl and Armor(wl) or 0
          if not worn or w < worn then worn = w end
        end
        local gain = new - (worn or 0)
        if gain > 0 and (not armGain or gain > armGain) then armI, armGain = i, gain end
      end
    end
    if armI then return armI, "armor" end
  end
  local ruleI, ruleGain
  for i = 1, n do
    local link = ns.Value(GetQuestItemLink, "choice", i)
    local s, slots = Score(link, class, level)
    if s and s > 0 then
      local gain = s - Worn(slots, class, level)
      if gain > 0 and (not ruleGain or gain > ruleGain) then ruleI, ruleGain = i, gain end
    end
  end
  if ruleI then return ruleI, "rule" end
  -- (1.3.8, F11) nothing by the rule: Geardon's sure upgrade
  if ns.GeardonUpgrade then
    for i = 1, n do
      local link = ns.Value(GetQuestItemLink, "choice", i)
      if link and ns.GeardonUpgrade(link) then return i, "geardon" end
    end
  end
end

local glow
local function ShowGlow(button)
  if not button then return end
  if not glow then
    glow = CreateFrame("Frame", "QuestdonRewardSuggest", UIParent)
    glow:SetFrameStrata("DIALOG")
    glow.edges = {}
    for i = 1, 4 do
      local t = glow:CreateTexture(nil, "OVERLAY")
      t:SetColorTexture(0.25, 1, 0.35, 0.95)
      glow.edges[i] = t
    end
    glow.soft = glow:CreateTexture(nil, "ARTWORK")
    glow.soft:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    glow.soft:SetBlendMode("ADD")
    glow.soft:SetVertexColor(0.3, 1, 0.4, 0.6)
    glow.soft:SetAllPoints()
  end
  glow:ClearAllPoints()
  glow:SetPoint("TOPLEFT", button, "TOPLEFT", -2, 2)
  glow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
  local e = glow.edges
  e[1]:ClearAllPoints() e[1]:SetPoint("TOPLEFT") e[1]:SetPoint("TOPRIGHT") e[1]:SetHeight(2)
  e[2]:ClearAllPoints() e[2]:SetPoint("BOTTOMLEFT") e[2]:SetPoint("BOTTOMRIGHT") e[2]:SetHeight(2)
  e[3]:ClearAllPoints() e[3]:SetPoint("TOPLEFT") e[3]:SetPoint("BOTTOMLEFT") e[3]:SetWidth(2)
  e[4]:ClearAllPoints() e[4]:SetPoint("TOPRIGHT") e[4]:SetPoint("BOTTOMRIGHT") e[4]:SetWidth(2)
  glow.index = button.GetID and button:GetID() or nil
  glow:Show()
end
function HideGlow() if glow then glow:Hide() glow.index = nil end end

function Suggest()
  HideGlow()
  if not (open and ns.db and ns.db.suggestReward) then return end
  local i, why = ns.SuggestRewardIndex()
  if i then
    ShowGlow(GetRewardButton(i))
    if glow then glow.why = why end
  end
end

-- what the player picked: the choices when the window opened and the bags then, compared after the turn-in
local snap
function Snapshot()
  snap = nil
  local n = ns.Num(ns.Value(GetNumQuestChoices)) or 0
  if n < 2 then return end
  local q = ns.Num(ns.Value(GetQuestID))
  if not q then return end
  local count = (C_Item and C_Item.GetItemCount) or GetItemCount
  snap = { q = q, items = {} }
  for i = 1, n do
    local id = ns.GetItemID(ns.Value(GetQuestItemLink, "choice", i))
    if id then snap.items[id] = count and ns.Num(ns.Value(count, id)) or 0 end
  end
end

local function Record(q, item)
  local db = ns.db
  if not db then return end
  db.rewardPicks = type(db.rewardPicks) == "table" and db.rewardPicks or {}
  local who = ns.Value(UnitGUID, "player")
  local key = q .. ":" .. tostring(who or "?")
  db.rewardPicks[key] = { q = q, i = item, c = ClassID() or 0, t = Tree(), lv = ns.PlayerLevel and ns.PlayerLevel() or nil }
  if ns.LearnedChanged then ns.LearnedChanged() end
end
ns.RecordRewardPick = Record -- (tests)

ns.On("QUEST_TURNED_IN", function(_, questID)
  local s = snap
  snap = nil
  local auto = ns._rewardAuto
  ns._rewardAuto = nil
  questID = ns.Num(questID)
  if not (s and questID and s.q == questID) or auto then return end
  ns.After(1.5, function()
    local count = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not count then return end
    for id, before in pairs(s.items) do
      local now = ns.Num(ns.Value(count, id)) or 0
      if now > before then Record(questID, id) return end
    end
  end)
end)
