local _, ns = ...
local L = ns.L

-- Gossip window (modern NPC dialog with quest list)
ns.On("GOSSIP_SHOW", function()
  if ns.IsPaused() or not C_GossipInfo then return end
  local db = ns.db

  if ns.Active("autoTurnIn") and C_GossipInfo.GetActiveQuests then
    for _, q in ipairs(ns.Value(C_GossipInfo.GetActiveQuests) or {}) do
      -- (1.23) secret flags count as "no" (like everywhere else)
      local id = type(q) == "table" and ns.True(q.isComplete) and ns.Num(q.questID)
      if id and id > 0 then
        C_GossipInfo.SelectActiveQuest(id)
        return
      end
    end
  end

  -- Quest log full: keep the dialog usable instead of opening a quest that cannot be taken.
  if ns.Active("autoAccept") and C_GossipInfo.GetAvailableQuests and not ns.QuestLogFull() then
    for _, q in ipairs(ns.Value(C_GossipInfo.GetAvailableQuests) or {}) do
      local id = type(q) == "table" and ns.Num(q.questID)
      if id and id > 0 and not ns.True(q.isIgnored) then
        -- (1.23) a secret "trivial" flag counts as trivial: left to the player
        local trivial = q.isTrivial ~= nil and (not ns.Usable(q.isTrivial) or q.isTrivial == true)
        if not (db.skipTrivial and trivial) then
          C_GossipInfo.SelectAvailableQuest(id)
          return
        end
      end
    end
  end
end)

-- Old style quest greeting window (NPC offers only quests)
ns.On("QUEST_GREETING", function()
  if ns.IsPaused() then return end
  local db = ns.db

  if ns.Active("autoTurnIn") then
    for i = 1, ns.Num(ns.Value(GetNumActiveQuests)) or 0 do
      local ok, _, isComplete = pcall(GetActiveTitle, i)
      if ok and ns.True(isComplete) then
        SelectActiveQuest(i)
        return
      end
    end
  end

  if ns.Active("autoAccept") and not ns.QuestLogFull() then
    for i = 1, ns.Num(ns.Value(GetNumAvailableQuests)) or 0 do
      -- (1.28) a secret flag must not be tested as a boolean: it counts as trivial (left to the player), as in the gossip list
      -- (ns.Value would turn a secret into nil, which counts as "not trivial": read it directly)
      local okT, isTrivial = pcall(GetAvailableQuestInfo, i)
      local trivial = okT and isTrivial ~= nil and (not ns.Usable(isTrivial) or isTrivial == true)
      if not (db.skipTrivial and trivial) then
        SelectAvailableQuest(i)
        return
      end
    end
  end
end)

-- Trivial (grey) for your level? Also for quests the NPC opens directly, without a list.
-- Without a readable answer from the client (missing API, not answered for a
-- quest that is not in the log yet, secret value): only quests far below your
-- level by the bundled data count as trivial.
local function IsTrivial(questID)
  questID = ns.Num(questID)
  if not (questID and questID > 0) then return false end
  local trivial = ns.Value(C_QuestLog.IsQuestTrivial, questID)
  if type(trivial) == "boolean" then return trivial end
  return ns.IsLowLevelQuest and ns.IsLowLevelQuest(questID, nil, true) or false
end

ns.On("QUEST_DETAIL", function()
  if ns.IsPaused() or not ns.Active("autoAccept") then return end
  if QuestGetAutoAccept and ns.True(ns.Value(QuestGetAutoAccept)) then -- (1.28) secret-safe
    if AcknowledgeAutoAcceptQuest then AcknowledgeAutoAcceptQuest() end
  elseif ns.db.skipTrivial and IsTrivial(ns.Value(GetQuestID)) then
    return -- left to you, like grey quests in the NPC's list
  elseif ns.QuestLogFull() then
    ns.Warn(L["Quest log is full: quest not accepted."])
  else
    AcceptQuest()
  end
end)

-- Escort quests started by another player
ns.On("QUEST_ACCEPT_CONFIRM", function()
  if ns.IsPaused() or not ns.Active("autoAccept") or ns.QuestLogFull() then return end
  ConfirmAcceptQuest()
end)

ns.On("QUEST_PROGRESS", function()
  if ns.IsPaused() or not ns.Active("autoTurnIn") then return end
  if not ns.True(ns.Value(IsQuestCompletable)) then return end
  -- Never spend gold automatically (unreadable cost: leave it to the player)
  if GetQuestMoneyToGet then
    local money = ns.Num(ns.Value(GetQuestMoneyToGet))
    if not money or money > 0 then return end
  end
  CompleteQuest()
end)

ns.On("QUEST_COMPLETE", function()
  if ns.IsPaused() or not ns.Active("autoTurnIn") then return end
  local choices = ns.Num(ns.Value(GetNumQuestChoices))
  if not choices or choices > 1 then return end -- Rewards.lua decides (or the player)
  GetQuestReward(choices)
end)
