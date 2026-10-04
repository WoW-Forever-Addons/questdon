local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Unit tooltips: which of your quests a mob counts for, and which quests an
-- NPC has for you. Uses the bundled database plus learned data, so it also
-- works where Questie has no data (new Forever quests).
---------------------------------------------------------------------------
local OBJ = ns.ATT_OBJECTIVES or {}
local Q = ns.ATT_QUESTS or {}
local GIVERS = 7

-- (1.23) objective entries are one number each, questID * SLOTS + index
-- (was a small table per entry: about a quarter less memory after login)
local SLOTS = 64
local byCreature -- [creatureID] = { questID * SLOTS + index, ... }
local byGiver    -- [creatureID] = { questID, ... }
local function Index()
  if byCreature then return end
  byCreature, byGiver = {}, {}
  for questID, objs in pairs(OBJ) do
    for index, o in pairs(objs) do
      if type(index) == "number" and index >= 1 and index < SLOTS then
        for _, cr in ipairs(o[1] or {}) do
          local list = byCreature[cr]
          if not list then list = {} byCreature[cr] = list end
          list[#list + 1] = questID * SLOTS + index
        end
      end
    end
  end
  for questID, q in pairs(Q) do
    for _, npc in ipairs(q[GIVERS] or {}) do
      byGiver[npc] = byGiver[npc] or {}
      table.insert(byGiver[npc], questID)
    end
  end
end

-- (1.22) Index entries of one creature (nameplate icons): objectives
-- (encoded, see ns.ObjectiveEntry) and quests it gives { questID, ... }, or nil.
function ns.CreatureQuestIndex(creatureID)
  Index()
  return byCreature[creatureID], byGiver[creatureID]
end
-- (1.23) questID, objective index of an encoded objective entry
function ns.ObjectiveEntry(v)
  local index = v % SLOTS
  return (v - index) / SLOTS, index
end

function ns.CreatureIDFromGUID(guid)
  if guid == nil or not ns.Usable(guid) or type(guid) ~= "string" then return nil end
  local kind, _, _, _, _, id = strsplit("-", guid)
  if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

local function QuestieShowsTooltip(questID)
  if not (ns.db.questieFirst and ns.AddOnLoaded("Questie")) then return false end
  local p = type(Questie) == "table" and type(Questie.db) == "table" and Questie.db.profile
  if type(p) ~= "table" or p.enableTooltips == false then return false end
  return ns.QuestieKnows(questID) == true
end

-- Lines for one creature: objectives first, then quests it gives.
function ns.TooltipLinesForCreature(creatureID)
  Index()
  local lines = {}
  for _, entry in ipairs(byCreature[creatureID] or {}) do
    local questID, index = ns.ObjectiveEntry(entry)
    local own = false
    if ns.InQuestLog(questID) and not ns.IsQuestComplete(questID) and not QuestieShowsTooltip(questID) then
      local o = ns.ClientObjectives(questID)[index]
      if not (type(o) == "table" and ns.True(o.finished)) then
        local text = type(o) == "table" and type(o.text) == "string" and ns.Usable(o.text) and o.text or ""
        lines[#lines + 1] = { ns.QuestTitle(questID), text, kind = "objective" }
        own = true
      end
    end
    -- (1.18) group members (Questdon) who still need this mob
    local party = ns.PartyObjectiveLines and ns.PartyObjectiveLines(questID, index) or {}
    if #party > 0 and not own then lines[#lines + 1] = { ns.QuestTitle(questID), "", kind = "partyQuest" } end
    for _, p in ipairs(party) do
      lines[#lines + 1] = { "  " .. p[1], p[2], party = true, kind = "party" }
    end
  end
  for _, questID in ipairs(byGiver[creatureID] or {}) do
    -- (1.24) the client's list or the data and the quest givers; an unknown
    -- level only once confirmed (or with "showNoLevel")
    local listed = ns.ClientAvailability(questID) == true and not ns.IsQuestDone(questID) and not ns.InQuestLog(questID)
    if (listed or ns.CanTakeQuest(questID)) and (listed or not ns.NoLevelHidden(questID))
        and not QuestieShowsTooltip(questID) then
      local dungeon = ns.QuestDungeon and ns.QuestDungeon(questID)
      local tag = ns.QuestLevelTag(questID) -- (1.22) "[?]" when the level is unknown
      lines[#lines + 1] = { "! " .. tag .. ns.QuestTitle(questID)
        .. (dungeon and (" (" .. ns.DungeonName(dungeon) .. ")") or ""), "", kind = "giver" }
    else
      -- (1.24) this NPC did not offer it at your level: say so (grey)
      local at = ns.NotOfferedLevel(questID)
      if at and not ns.IsQuestDone(questID) and not ns.InQuestLog(questID) then
        lines[#lines + 1] = { ns.QuestTitle(questID), L["Not offered by the quest giver (level %d)"]:format(at), kind = "notOffered" }
      end
    end
  end
  return lines
end

local function OnUnitTooltip(tooltip, data)
  if not ns.db.unitTooltips or tooltip ~= GameTooltip then return end
  local guid = type(data) == "table" and data.guid or nil
  if guid == nil and tooltip.GetUnit then
    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    if ok and type(unit) == "string" and ns.Usable(unit) then guid = ns.Value(UnitGUID, unit) end
  end
  local id = ns.CreatureIDFromGUID(guid)
  if not id then return end
  local lines = ns.TooltipLinesForCreature(id)
  if #lines == 0 then return end
  -- (1.19) family structure inside Blizzard's unit tooltip: a spacer, then
  -- key/value lines (quest in the secondary colour, progress in the primary
  -- colour); quests to pick up with the yellow "!" and Blizzard's level colour.
  local C = ns.Style.COLORS
  local P, K, W = C.textPrimary, C.textSecondary, C.warning
  tooltip:AddLine(" ")
  for i = 1, math.min(#lines, 8) do
    local l = lines[i]
    if l.kind == "giver" then
      tooltip:AddLine("|c" .. W.hex .. "!|r" .. l[1]:sub(2), P[1], P[2], P[3])
    elseif l.kind == "notOffered" then
      local H = C.textHint or K
      tooltip:AddDoubleLine(l[1], l[2], K[1], K[2], K[3], H[1], H[2], H[3])
    elseif l[2] ~= "" then
      tooltip:AddDoubleLine(l[1], l[2], K[1], K[2], K[3], P[1], P[2], P[3])
    else
      tooltip:AddLine(l[1], K[1], K[2], K[3])
    end
  end
end

ns.OnInit(function()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    ns.tooltipHooked = pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit,
      ns.Guard("tooltip", OnUnitTooltip))
  end
end)

---------------------------------------------------------------------------
-- Rewards of a quest in the log (XP, money, items, choices)
---------------------------------------------------------------------------
function ns.QuestRewardLines(questID)
  local lines = {}
  if not ns.InQuestLog(questID) then return lines end
  local xp = ns.Num(ns.Value(GetQuestLogRewardXP, questID))
  if xp and xp > 0 then
    lines[#lines + 1] = L["%s XP"]:format(BreakUpLargeNumbers and BreakUpLargeNumbers(xp) or xp)
  end
  local money = ns.Num(ns.Value(GetQuestLogRewardMoney, questID))
  if money and money > 0 then lines[#lines + 1] = ns.Money(money) end
  local items = {}
  if GetQuestLogRewardInfo then
    for i = 1, math.min(ns.Num(ns.Value(GetNumQuestLogRewards, questID)) or 0, 10) do
      local ok, name, _, count = pcall(GetQuestLogRewardInfo, i, questID)
      if ok and type(name) == "string" and ns.Usable(name) then
        count = ns.Num(count)
        items[#items + 1] = (count and count > 1) and ("%dx %s"):format(count, name) or name
      end
    end
  end
  if #items > 0 then lines[#lines + 1] = table.concat(items, ", ") end
  local choices = {}
  if GetQuestLogChoiceInfo then
    for i = 1, math.min(ns.Num(ns.Value(GetNumQuestLogChoices, questID, true)) or 0, 10) do
      local ok, name = pcall(GetQuestLogChoiceInfo, i, questID)
      if ok and type(name) == "string" and ns.Usable(name) then choices[#choices + 1] = name end
    end
  end
  if #choices > 0 then lines[#lines + 1] = L["Choice: %s"]:format(table.concat(choices, " / ")) end
  return lines
end
