local _, ns = ...
local L = ns.L

-- (1.18) Quests a group member shared with you: the quest dialog came from a
-- player. Sharing them back would only send "already on that quest" to all.
local fromPlayer = {}
ns.On("QUEST_DETAIL", function()
  local id = ns.Num(ns.Value(GetQuestID))
  if id and id > 0 and ns.True(ns.Value(UnitIsPlayer, "npc")) then fromPlayer[id] = true end
end)

-- Shares a newly accepted quest with the group.
ns.On("QUEST_ACCEPTED", function(_, questID)
  questID = ns.Num(questID)
  if not ns.db.shareQuests or not questID or not ns.True(ns.Value(IsInGroup)) then return end
  if fromPlayer[questID] then fromPlayer[questID] = nil return end
  ns.After(1, function()
    if InCombatLockdown() or not ns.True(ns.Value(IsInGroup)) then return end
    if not ns.InQuestLog(questID) then return end
    if C_QuestLog.IsPushableQuest and not ns.True(ns.Value(C_QuestLog.IsPushableQuest, questID)) then return end
    -- Forever beta 2026-09-24: dungeon quests can no longer be shared
    if ns.QuestDungeon and ns.QuestDungeon(questID) then return end
    -- (1.18) everyone in the group (with Questdon) has it already: nothing to share
    local have = ns.PartyMembersWithQuest and #ns.PartyMembersWithQuest(questID) or 0
    local others = math.max((ns.Num(ns.Value(GetNumGroupMembers)) or 1) - 1, 0)
    if have > 0 and have >= others then return end
    if type(QuestLogPushQuest) ~= "function" or not C_QuestLog.SetSelectedQuest then return end
    -- (1.20) secret or missing values must not reach the comparisons below
    local previous = ns.Num(ns.Value(C_QuestLog.GetSelectedQuest))
    if not pcall(C_QuestLog.SetSelectedQuest, questID) then return end
    local pushed = pcall(QuestLogPushQuest)
    if previous and previous > 0 and previous ~= questID
        and (ns.Num(ns.Value(C_QuestLog.GetLogIndexForQuestID, previous)) or 0) > 0 then
      pcall(C_QuestLog.SetSelectedQuest, previous)
    end
    if not pushed then return end
    ns.Print(L["Shared with your group: %s"]:format(ns.QuestTitle(questID)))
  end)
end)
