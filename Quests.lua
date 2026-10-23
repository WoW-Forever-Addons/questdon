local _, ns = ...
local L = ns.L

-- (1.3.5, Daniel 10.10.) Repeatable quests (hand in more cloth, again and again) are never
-- turned in automatically: the dialog comes back after each turn-in, so it would hand in every
-- stack. The data's flag or the client's own "repeatable" answer.
-- (Questdon review 3) the client's flag is remembered for the quest (this session): the progress and reward dialogs
-- that follow have only the quest ID, and a repeatable quest the data does not flag was handed in stack after stack
-- (review 4) kept in the saved variables, so the map hides its ! like that of a repeatable quest of the data
local function Repeatable(questID, clientFlag)
  questID = ns.Num(questID)
  if clientFlag ~= nil and (not ns.Usable(clientFlag) or clientFlag == true) then
    if questID and clientFlag == true and ns.db then
      ns.db.clientRepeatable = type(ns.db.clientRepeatable) == "table" and ns.db.clientRepeatable or {}
      ns.db.clientRepeatable[questID] = true
    end
    return true
  end
  return questID ~= nil and questID > 0 and ns.IsRepeatableQuest and ns.IsRepeatableQuest(questID) or false
end
ns.SkipAutoTurnIn = Repeatable

-- (Questdon review 1) never pay gold automatically, also not in the reward dialog (a server may open it right
-- away, or the player clicked on in the progress dialog): the cost the dialog shows, the one the quest log has,
-- or one seen in the progress dialog of the quest; a cost that cannot be read counts as a cost
local costSeen = {}
function ns.QuestCostsGold(questID, progress)
  questID = ns.Num(questID)
  if GetQuestMoneyToGet then
    local money = ns.Num(ns.Value(GetQuestMoneyToGet))
    -- the progress dialog's cost is the quest's cost (the reward dialog may read 0)
    if progress and questID and money then costSeen[questID] = money > 0 or nil end
    if not money or money > 0 then return true end
  end
  if questID and costSeen[questID] then return true end
  if questID and questID > 0 and C_QuestLog and C_QuestLog.GetRequiredMoney then
    local m = ns.Value(C_QuestLog.GetRequiredMoney, questID)
    if m ~= nil and (ns.Num(m) or 0) > 0 then return true end
  end
  return false
end

-- (1.3.6, Daniel 11.10.) With Leveldon guiding: quests outside its route are not accepted automatically,
-- they are left to you (Leveldon says whether one you take yourself fits the route).
local function LeftToPlayer(questID)
  questID = ns.Num(questID)
  local api = rawget(_G, "LeveldonAPI")
  if not (questID and questID > 0 and type(api) == "table" and type(api.WantsQuest) == "function") then return false end
  local ok, wants = pcall(api.WantsQuest, questID)
  return ok and wants == false
end
ns.LeftToPlayer = LeftToPlayer

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

-- (1.3.8, F3) A breadcrumb you can still take leads to this quest: once you take the quest it is gone (and its XP).
-- Said once per quest; auto accept leaves such a quest to you. Not when Leveldon's route wants the quest, and not for
-- grey breadcrumbs.
local crumbSaid = {}
local function OpenCrumb(questID)
  questID = ns.Num(questID)
  if not (questID and questID > 0 and ns.OpenBreadcrumbs) then return nil end
  local api = rawget(_G, "LeveldonAPI")
  local routeWants = false
  if type(api) == "table" and type(api.WantsQuest) == "function" then
    local ok, wants = pcall(api.WantsQuest, questID)
    routeWants = ok and wants == true
  end
  for _, id in ipairs(ns.OpenBreadcrumbs(questID) or {}) do
    if not IsTrivial(id) then
      if not routeWants then return id end
      local ok, w = pcall(api.WantsQuest, id) -- (review 6) the route takes the breadcrumb too
      if ok and w == true then return id end
    end
  end
end
local function SayCrumb(questID, crumb, held)
  if crumbSaid[questID] then return end
  crumbSaid[questID] = true
  local zone = ns.JournalMapName and ns.QuestStart and ns.JournalMapName((ns.QuestStart(crumb)))
  local name = "\"" .. ns.QuestTitle(crumb) .. "\"" .. (zone and " (" .. zone .. ")" or "")
  ns.Print((held and L["Not accepted automatically: the breadcrumb %s leads to this quest and is gone once you take it."]
    or L["The breadcrumb %s leads to this quest and is gone once you take it."]):format(name))
end
-- In the NPC's list: such a quest is not opened automatically (it would open again after each decline).
local function HeldForCrumb(questID)
  local crumb = OpenCrumb(questID)
  if crumb then SayCrumb(ns.Num(questID), crumb, true) return true end
  return false
end


-- Gossip window (modern NPC dialog with quest list)
ns.On("GOSSIP_SHOW", function()
  if ns.IsPaused() or not C_GossipInfo then return end
  local db = ns.db

  if ns.Active("autoTurnIn") and C_GossipInfo.GetActiveQuests then
    for _, q in ipairs(ns.Value(C_GossipInfo.GetActiveQuests) or {}) do
      -- (1.23) secret flags count as "no" (like everywhere else)
      local id = type(q) == "table" and ns.True(q.isComplete) and ns.Num(q.questID)
      if id and id > 0 and not Repeatable(id, q.repeatable) then
        C_GossipInfo.SelectActiveQuest(id)
        return
      end
    end
  end

  -- Quest log full: keep the dialog usable instead of opening a quest that cannot be taken.
  if ns.Active("autoAccept") and C_GossipInfo.GetAvailableQuests and not ns.QuestLogFull() then
    for _, q in ipairs(ns.Value(C_GossipInfo.GetAvailableQuests) or {}) do
      local id = type(q) == "table" and ns.Num(q.questID)
      -- (review 3) a repeatable quest is left to you here too (it opened on every visit)
      if id and id > 0 and not ns.True(q.isIgnored) and not LeftToPlayer(id) and not Repeatable(id, q.repeatable) then
        -- (1.23) a secret "trivial" flag counts as trivial: left to the player
        local trivial = q.isTrivial ~= nil and (not ns.Usable(q.isTrivial) or q.isTrivial == true)
        if not (db.skipTrivial and trivial) and not HeldForCrumb(id) then
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
      if ok and ns.True(isComplete) and not Repeatable(ns.Value(GetActiveQuestID, i)) then
        SelectActiveQuest(i)
        return
      end
    end
  end

  if ns.Active("autoAccept") and not ns.QuestLogFull() then
    for i = 1, ns.Num(ns.Value(GetNumAvailableQuests)) or 0 do
      -- (1.28) a secret flag must not be tested as a boolean: it counts as trivial (left to the player), as in the gossip list
      -- (ns.Value would turn a secret into nil, which counts as "not trivial": read it directly)
      local okT, isTrivial, _, isRepeat, _, availID = pcall(GetAvailableQuestInfo, i)
      local trivial = okT and isTrivial ~= nil and (not ns.Usable(isTrivial) or isTrivial == true)
      local qid = okT and ns.Usable(availID) and availID or nil
      if not (db.skipTrivial and trivial) and not LeftToPlayer(qid) and not (okT and Repeatable(qid, isRepeat))
          and not HeldForCrumb(qid) then
        SelectAvailableQuest(i)
        return
      end
    end
  end
end)

ns.On("QUEST_DETAIL", function()
  local questID = ns.Num(ns.Value(GetQuestID))
  if ns.IsPaused() or not ns.Active("autoAccept") then
    local crumb = OpenCrumb(questID)
    if crumb then SayCrumb(questID, crumb, false) end
    return
  end
  if QuestGetAutoAccept and ns.True(ns.Value(QuestGetAutoAccept)) then -- (1.28) secret-safe
    if AcknowledgeAutoAcceptQuest then AcknowledgeAutoAcceptQuest() end
  elseif ns.db.skipTrivial and IsTrivial(ns.Value(GetQuestID)) then
    return -- left to you, like grey quests in the NPC's list
  elseif LeftToPlayer(ns.Value(GetQuestID)) then
    return -- (1.3.6) not in Leveldon's route: left to you
  elseif OpenCrumb(questID) then
    SayCrumb(questID, OpenCrumb(questID), true)
    return
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
  if Repeatable(ns.Value(GetQuestID)) then return end -- (1.3.5) left to you
  -- Never spend gold automatically (unreadable cost: leave it to the player)
  if ns.QuestCostsGold(ns.Value(GetQuestID), true) then return end
  CompleteQuest()
end)

ns.On("QUEST_COMPLETE", function()
  if ns.IsPaused() or not ns.Active("autoTurnIn") then return end
  if Repeatable(ns.Value(GetQuestID)) then return end -- (1.3.5) left to you
  if ns.QuestCostsGold(ns.Value(GetQuestID)) then return end -- (Questdon review 1) the reward dialog pays it
  local choices = ns.Num(ns.Value(GetNumQuestChoices))
  if not choices or choices > 1 then return end -- Rewards.lua decides (or the player)
  GetQuestReward(choices)
end)
