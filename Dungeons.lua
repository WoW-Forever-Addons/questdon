local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- (1.18) Dungeon quests. All The Things files the quests of a dungeon under
-- that dungeon; the bundled data keeps the dungeon as the 15th field of a
-- quest row and the dungeons themselves in ns.ATT_DUNGEONS:
--   [instanceID] = { name (English), uiMapID, entranceMap, x, y, minLevel }
-- Forever pays dungeon quests far more XP than dungeon kills, so the point is:
-- never walk into a dungeon without its quests.
--   * ns.DungeonOverview(): per dungeon the quests in the log and the ones
--     the character can pick up right now (same rules as the map pins).
--   * Panel row "Dungeon quests", tooltip per dungeon, click: arrow to the
--     nearest quest giver of a dungeon quest (else the entrance).
--   * Entering a dungeon: chat line with its quests in the log and the ones
--     still missing (beta 2026-09-24: dungeon quests cannot be shared, so
--     the hint says to pick them up at the quest giver).
--   * /qd dungeons: the full list as text.
---------------------------------------------------------------------------
local Q = ns.ATT_QUESTS or {}
local D = ns.ATT_DUNGEONS or {}
local DUNGEON, LEVEL, NAME_EN = 15, 5, 1
local UIMAP, EMAP, EX, EY, MINLEVEL = 2, 3, 4, 5, 6

local byDungeon -- [instanceID] = { questIDs }
local byUiMap   -- [uiMapID] = instanceID
local function Index()
  if byDungeon then return end
  byDungeon, byUiMap = {}, {}
  for id, q in pairs(Q) do
    local d = q[DUNGEON]
    if d then
      byDungeon[d] = byDungeon[d] or {}
      table.insert(byDungeon[d], id)
    end
  end
  for _, list in pairs(byDungeon) do table.sort(list) end
  for inst, d in pairs(D) do
    if d[UIMAP] then byUiMap[d[UIMAP]] = inst end
  end
end

-- Dungeon of a quest: instanceID or nil.
function ns.QuestDungeon(questID)
  local q = Q[questID]
  return q and q[DUNGEON] or nil
end

-- Localised name: the client's name of the dungeon map, else ATT's English name.
function ns.DungeonName(inst)
  local d = D[inst]
  if not d then return inst and ("Dungeon " .. tostring(inst)) or "?" end
  if d[UIMAP] and C_Map then
    local info = ns.Value(C_Map.GetMapInfo, d[UIMAP])
    local name = type(info) == "table" and info.name
    if type(name) == "string" and ns.Usable(name) and name ~= "" then return name end
  end
  return d[NAME_EN] or ("Dungeon " .. tostring(inst))
end

function ns.DungeonMinLevel(inst)
  local d = D[inst]
  return d and d[MINLEVEL] or nil
end

-- Entrance: mapID, x, y (0-1) or nil.
function ns.DungeonEntrance(inst)
  local d = D[inst]
  if d and d[EMAP] and d[EX] and d[EY] then return d[EMAP], d[EX] / 100, d[EY] / 100 end
end

function ns.DungeonQuestIDs(inst)
  Index()
  return byDungeon[inst] or {}
end

-- The dungeon the player is in: instanceID or nil (map of the player or one
-- of its parents is a dungeon map of the data).
function ns.CurrentDungeon()
  Index()
  local m = C_Map and ns.Num(ns.Value(C_Map.GetBestMapForUnit, "player"))
  for _ = 1, 4 do
    if not m or m <= 0 then break end
    if byUiMap[m] then return byUiMap[m] end
    local info = ns.Value(C_Map.GetMapInfo, m)
    m = type(info) == "table" and ns.Num(info.parentMapID) or nil
  end
  -- fallback in an instance: its name against the dungeon names (client or English)
  if not ns.True(ns.Value(IsInInstance)) then return nil end
  local name = ns.Value(GetInstanceInfo)
  if type(name) ~= "string" or name == "" then return nil end
  for inst, d in pairs(D) do
    if byDungeon[inst] and (name == d[NAME_EN] or name == ns.DungeonName(inst)) then return inst end
  end
end

-- Objective progress of a quest in the log as short text ("3/8, 0/1"), or nil.
local function Progress(questID)
  local parts = {}
  for _, o in ipairs(ns.ClientObjectives(questID)) do
    if type(o) == "table" then
      local f, r = ns.Num(o.numFulfilled), ns.Num(o.numRequired)
      if f and r and r > 0 then parts[#parts + 1] = ("%d/%d"):format(f, r) end
    end
  end
  return #parts > 0 and table.concat(parts, ", ") or nil
end
ns.QuestProgressText = Progress

-- (1.28) "Anna 3/8, Bob done" for the members who have a quest (empty list if none or
-- group progress is off). Only quest IDs and counters ever come from the group.
local function GroupStates(id)
  local out = {}
  if not (ns.PartyProgress and ns.PartyStateText) then return out end
  for _, p in ipairs(ns.PartyProgress(id)) do out[#out + 1] = L["%s %s (player and quest state)"]:format(p.name, ns.PartyStateText(p)) end
  return out
end

-- (1.28) Members with quests of one dungeon: { { name, count }, ... } sorted by name.
function ns.DungeonGroupSummary(inst)
  local list = {}
  if not (inst and ns.PartyQuestSet and ns.PartyProgress) then return list end
  local counts = {}
  for id in pairs(ns.PartyQuestSet()) do
    if ns.QuestDungeon(id) == inst then
      for _, p in ipairs(ns.PartyProgress(id)) do counts[p.name] = (counts[p.name] or 0) + 1 end
    end
  end
  for name, count in pairs(counts) do list[#list + 1] = { name = name, count = count } end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

-- { { inst, name, level, inLog = { questIDs }, available = { questIDs },
--     group = { questIDs the group has and you neither have nor can see as available } }, ... }
-- Only dungeons with something to do, sorted by dungeon level, then name.
function ns.DungeonOverview()
  Index()
  local list = {}
  -- cheap filters first (about 600 dungeon quests): the log once, the level
  local log = {}
  for _, info in ipairs(ns.QuestLogEntries()) do log[info.questID] = true end
  local level = ns.PlayerLevel()
  -- (1.28) quests of the group by dungeon (only with group data; empty otherwise)
  local groupBy = {}
  if ns.PartyQuestSet then
    for id in pairs(ns.PartyQuestSet()) do
      local inst = Q[id] and Q[id][DUNGEON]
      if inst then
        groupBy[inst] = groupBy[inst] or {}
        table.insert(groupBy[inst], id)
      end
    end
  end
  for inst, ids in pairs(byDungeon) do
    local inLog, available = {}, {}
    for _, id in ipairs(ids) do
      local minLevel = Q[id][LEVEL]
      if log[id] then
        inLog[#inLog + 1] = id
      elseif not (level and minLevel and minLevel > level)
          and ns.ShowAsAvailable(id) then -- (1.24) one rule with the map (client, quest givers, level)
        available[#available + 1] = id
      end
    end
    if #inLog + #available > 0 then
      local group = {}
      local isAvailable = {}
      for _, id in ipairs(available) do isAvailable[id] = true end
      for _, id in ipairs(groupBy[inst] or {}) do
        if not log[id] and not isAvailable[id] and not ns.IsQuestDone(id) and not ns.QuestKnownMissing(id) then
          group[#group + 1] = id
        end
      end
      table.sort(group)
      list[#list + 1] = { inst = inst, name = ns.DungeonName(inst), level = ns.DungeonMinLevel(inst) or 0,
        inLog = inLog, available = available, group = group }
    end
  end
  table.sort(list, function(a, b)
    if a.level ~= b.level then return a.level < b.level end
    return tostring(a.name) < tostring(b.name)
  end)
  return list
end

-- Counts over an overview: quests in the log, quests to pick up.
function ns.DungeonCounts(overview)
  local inLog, available = 0, 0
  for _, d in ipairs(overview or ns.DungeonOverview()) do
    inLog, available = inLog + #d.inLog, available + #d.available
  end
  return inLog, available
end

-- (1.22) "[?]" for a quest without a known level (never guessed)
local function LevelTag(id)
  local lv = ns.QuestLevel(id)
  return lv and ("[%d] "):format(lv) or "[?] "
end

-- Nearest start (same continent) of a dungeon quest you can pick up:
-- { questID, mapID, x, y, dist } or nil.
function ns.NearestDungeonQuest(overview)
  local best
  -- (1.23) the player's position once, not once per quest
  local pc, pn, pw
  if ns.PlayerWorld then pc, pn, pw = ns.PlayerWorld() end
  if not pc then return nil end
  for _, d in ipairs(overview or ns.DungeonOverview()) do
    for _, id in ipairs(d.available) do
      local m, x, y = ns.QuestStart(id)
      if m and x and not ns.IsItemStartQuest(id) then
        local t = { mapID = m, x = x / 100, y = y / 100 }
        local dist = ns.DistanceFrom(pc, pn, pw, t)
        if dist and (not best or dist < best.dist) then
          best = { questID = id, mapID = m, x = t.x, y = t.y, dist = dist }
        end
      end
    end
  end
  return best
end

-- Click on the panel row: nearest dungeon quest giver, else the entrance of the
-- first dungeon with quests in the log. true if the arrow got a target.
function ns.PointToDungeonQuest()
  local overview = ns.DungeonOverview()
  local n = ns.NearestDungeonQuest(overview)
  local m, x, y, label
  if n then
    m, x, y, label = n.mapID, n.x, n.y, ns.QuestTitle(n.questID)
  else
    for _, d in ipairs(overview) do
      if #d.inLog > 0 then
        local em, ex, ey = ns.DungeonEntrance(d.inst)
        if em then m, x, y, label = em, ex, ey, L["Entrance: %s"]:format(d.name) break end
      end
    end
  end
  if not (m and ns.SetArrowTarget) then ns.Print(L["No dungeon quest giver or entrance nearby."]) return false end
  ns.db.arrow = true
  if ns.ApplyArrow then ns.ApplyArrow() end
  ns.SetArrowTarget(m, x, y, label)
  return true
end

-- Tooltip lines for the panel row: dungeon header, then its quests.
function ns.DungeonTooltipLines(overview)
  local lines = {}
  for _, d in ipairs(overview or ns.DungeonOverview()) do
    local head = d.name
    if d.level > 0 then head = head .. " " .. L["(level %d+)"]:format(d.level) end
    lines[#lines + 1] = { text = head, header = true, inst = d.inst }
    for _, id in ipairs(d.inLog) do
      local state = ns.IsQuestComplete(id) and L["done"] or Progress(id) or L["in log"]
      local title = LevelTag(id) .. ns.QuestTitle(id)
      local g = GroupStates(id)
      if #g > 0 then state = state .. " " .. L["(group: %s)"]:format(table.concat(g, ", ")) end
      -- (1.20) title and state as own fields: titles may contain ": " themselves
      lines[#lines + 1] = { text = "  " .. title .. L[": "] .. state, inLog = true, questID = id, title = title, state = state }
    end
    for _, id in ipairs(d.available) do
      local m = ns.QuestStart(id)
      local info = m and C_Map and ns.Value(C_Map.GetMapInfo, m)
      local where = type(info) == "table" and type(info.name) == "string" and ns.Usable(info.name) and info.name or nil
      local who = ns.PartyMembersWithQuest and ns.PartyMembersWithQuest(id) or {}
      local title = LevelTag(id) .. ns.QuestTitle(id)
      local state = (where and L["pick up in %s"]:format(where) or L["not picked up"])
        .. (#who > 0 and (" " .. L["(group: %s)"]:format(table.concat(who, ", "))) or "")
      lines[#lines + 1] = { text = "  " .. title .. L[": "] .. state, questID = id, title = title, state = state }
    end
    -- (1.28) quests only the group has (cannot be shared: they pick them up themselves)
    for _, id in ipairs(d.group or {}) do
      local title = LevelTag(id) .. ns.QuestTitle(id)
      local state = L["not picked up"] .. " " .. L["(group: %s)"]:format(table.concat(GroupStates(id), ", "))
      lines[#lines + 1] = { text = "  " .. title .. L[": "] .. state, questID = id, title = title, state = state }
    end
  end
  return lines
end

-- /qd dungeons: everything as text.
function ns.OpenDungeons()
  local overview = ns.DungeonOverview()
  local out = {}
  for _, l in ipairs(ns.DungeonTooltipLines(overview)) do out[#out + 1] = l.text end
  local inLog, available = ns.DungeonCounts(overview)
  local note = #overview == 0 and L["No dungeon quest in your log or to pick up right now."]
    or L["Dungeon quests: %d in your log, %d to pick up. Forever pays dungeon quests extra XP: take them before you go in."]:format(inLog, available)
  return ns.ShowText(L["Dungeon quests"], note, #out > 0 and table.concat(out, "\n") or "-")
end

-- Entering a dungeon: one chat line about its quests (once per visit).
local lastDungeon
local function OnZone()
  local inst = ns.CurrentDungeon()
  if inst == lastDungeon then return end
  lastDungeon = inst
  if not (inst and ns.db.dungeonHint) then return end
  local inLog, missing, groupLine = 0, {}, nil
  for _, id in ipairs(ns.DungeonQuestIDs(inst)) do
    if ns.InQuestLog(id) then
      inLog = inLog + 1
    elseif ns.ShowAsAvailable(id) then
      local who = ns.PartyMembersWithQuest and ns.PartyMembersWithQuest(id) or {}
      missing[#missing + 1] = ns.QuestTitle(id) .. (#who > 0 and (" (" .. table.concat(who, ", ") .. ")") or "")
    end
  end
  -- (1.28) who in the group has quests of this dungeon (opt-in group progress)
  local who = {}
  for _, g in ipairs(ns.DungeonGroupSummary(inst)) do who[#who + 1] = ("%s (%d)"):format(g.name, g.count) end
  if #who > 0 then
    local line = L["Group members with quests of this dungeon: %s"]:format(table.concat(who, ", "))
    if inLog == 0 and #missing == 0 then ns.Print(ns.DungeonName(inst) .. L[": "] .. line) return end
    groupLine = line
  end
  if inLog == 0 and #missing == 0 then return end
  local msg = L["%s: %d quests for this dungeon in your log."]:format(ns.DungeonName(inst), inLog)
  if #missing > 0 then
    msg = msg .. " " .. L["Not in your log: %s. Dungeon quests cannot be shared: pick them up at the quest giver."]:format(table.concat(missing, "; "))
  end
  ns.Print(msg)
  if groupLine then ns.Print(groupLine) end
end
ns.DungeonZoneCheck = OnZone

ns.On("PLAYER_ENTERING_WORLD", function() ns.After(2, OnZone) end)
ns.On("ZONE_CHANGED_NEW_AREA", function() ns.After(1, OnZone) end)
