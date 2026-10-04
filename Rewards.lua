local _, ns = ...
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

local function Evaluate()
  HideMarker()
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

  if db.autoPickBest and ns.Active("autoTurnIn") and not ns.IsPaused() then
    GetQuestReward(index)
    return
  end
  if db.highlightBest then
    ShowMarker(GetRewardButton(index))
    ns.Print(L["Most valuable reward: %s (%s)"]:format(link, ns.Money(value)))
  end
end

ns.On("QUEST_COMPLETE", function()
  open = true
  -- Wait one frame so Blizzard has laid out the reward buttons.
  ns.After(0, Evaluate)
end)

ns.On("ITEM_DATA_LOAD_RESULT", function()
  if waiting and QuestFrame and QuestFrame:IsShown() then
    waiting = false
    ns.After(0.1, Evaluate)
  end
end)

ns.On("QUEST_FINISHED", function()
  open = false
  waiting = false
  HideMarker()
end)
