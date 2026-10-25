local _, ns = ...
local C_QuestLog = ns.QL or C_QuestLog -- (25.10.2026) Era shims, Core.lua ApiProxy
local L = ns.L

-- (1.18) Quests a group member shared with you: the quest dialog came from a
-- player. Sharing them back would only send "already on that quest" to all.
local fromPlayer = {}
local confirmAt, confirmTitle -- (Questdon review 2) when the game last asked to join a member's escort, (3) and which
ns.On("QUEST_DETAIL", function()
  local id = ns.Num(ns.Value(GetQuestID))
  -- (Questdon review 2) only the dialog open now: a shared quest declined and later taken from its NPC is shared
  fromPlayer = {}
  confirmAt = nil -- a quest dialog: what follows is not a joined escort
  if id and id > 0 and ns.True(ns.Value(UnitIsPlayer, "npc")) then fromPlayer[id] = true end
end)
-- (Questdon review 2) an escort a group member started (the game asks to join it): not pushed back to the group
ns.On("QUEST_ACCEPT_CONFIRM", function(_, _, title)
  confirmAt = ns.Num(ns.Value(GetTime))
  confirmTitle = type(title) == "string" and ns.Usable(title) and title or nil
end)

-- Shares a newly accepted quest with the group.
-- (Questdon review 1) a quest accepted in a fight is shared once the fight is over (it was dropped)
local afterFight = {}
local function Push(questID)
  if not ns.db.shareQuests or not ns.True(ns.Value(IsInGroup)) then return end
  if InCombatLockdown() then afterFight[questID] = true return end
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
end

ns.On("QUEST_ACCEPTED", function(_, questID)
  questID = ns.Num(questID)
  if not ns.db.shareQuests or not questID or not ns.True(ns.Value(IsInGroup)) then return end
  if fromPlayer[questID] then fromPlayer[questID] = nil return end
  local now = ns.Num(ns.Value(GetTime))
  -- (review 3) only the escort itself (its title), not another quest taken from an NPC meanwhile
  if confirmAt and now and now - confirmAt >= 0 and now - confirmAt < 10
      and (not confirmTitle or ns.QuestTitle(questID) == confirmTitle) then
    confirmAt, confirmTitle = nil, nil
    return
  end
  ns.After(1, function() Push(questID) end)
end)

ns.On("PLAYER_REGEN_ENABLED", function()
  if not next(afterFight) then return end
  local list = afterFight
  afterFight = {}
  ns.After(0.5, function() for questID in pairs(list) do Push(questID) end end)
end)
