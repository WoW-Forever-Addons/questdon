local _, ns = ...

---------------------------------------------------------------------------
-- Learning: where quests are accepted and turned in (account wide)
---------------------------------------------------------------------------
local pendingStart = {}  -- [questID] = { map, x, y, npc, item }
local pendingFinish = {} -- [questID] = { map, x, y, npc }

-- A quest shared by a group member also opens the quest dialog, then "npc" is
-- that player: no quest giver, so nothing about the start is learned.
-- Anything unreadable (secret value, missing API) counts as "no quest giver".
-- "yes", "no" or "unknown" (missing API, error, secret value).
local function Flag(fn, ...)
  if type(fn) ~= "function" then return "unknown" end
  local ok, v = pcall(fn, ...)
  if not ok or (v ~= nil and not ns.Usable(v)) then return "unknown" end
  return (v and v ~= 0) and "yes" or "no"
end

local function NpcName()
  if Flag(UnitExists, "npc") ~= "yes" then return nil end
  if UnitIsUnit and Flag(UnitIsUnit, "npc", "player") ~= "no" then return nil end
  if UnitIsPlayer and Flag(UnitIsPlayer, "npc") ~= "no" then return nil end
  local guid = ns.Value(UnitGUID, "npc")
  if type(guid) == "string" and guid:find("^Player%-") then return nil end
  local name = ns.Value(UnitName, "npc")
  return type(name) == "string" and name ~= "" and name or nil
end

-- Creature ID of the quest giver (for the community export; names are localised).
local function NpcID()
  if not (UnitGUID and ns.CreatureIDFromGUID) then return nil end
  return ns.CreatureIDFromGUID(ns.Value(UnitGUID, "npc"))
end

-- (1.0.1) "c", creatureID or "o", objectID from a GUID (nil for players,
-- items, secret or unreadable GUIDs).
function ns.GUIDKindID(guid)
  if guid == nil or not ns.Usable(guid) or type(guid) ~= "string" or not strsplit then return nil end
  local kind, _, _, _, _, id = strsplit("-", guid)
  id = tonumber(id)
  if not id or id <= 0 or id ~= math.floor(id) then return nil end
  if kind == "Creature" or kind == "Vehicle" then return "c", id end
  if kind == "GameObject" then return "o", id end
  return nil
end

local function UnitKindID(unit)
  if not UnitGUID then return nil end
  return ns.GUIDKindID(ns.Value(UnitGUID, unit))
end

-- Session clock in seconds.
local function Clock() return ns.Num(ns.Value(GetTime)) or 0 end

local function PlayerLevel() return ns.Num(ns.Value(UnitLevel, "player")) end

local function Here()
  local map, x, y = ns.PlayerPosition()
  if not map then return nil end
  local npc = NpcName()
  local here = { map = map, x = x, y = y, npc = npc }
  if npc then
    -- (1.0.1) a quest giver is a creature or an object (wanted poster, book)
    local kind, id = UnitKindID("npc")
    if kind == "c" then here.npcID = id elseif kind == "o" then here.objID = id end
  end
  return here
end

-- (1.0.1) The bag item that starts this quest (C_Container quest info).
local function StartItem(questID)
  local C = C_Container
  if not (C and C.GetContainerNumSlots and C.GetContainerItemQuestInfo and C.GetContainerItemID) then return nil end
  for bag = 0, 5 do
    for slot = 1, ns.Num(ns.Value(C.GetContainerNumSlots, bag)) or 0 do
      local info = ns.Value(C.GetContainerItemQuestInfo, bag, slot)
      if type(info) == "table" and ns.Num(info.questID) == questID then
        local id = ns.Num(ns.Value(C.GetContainerItemID, bag, slot))
        if id and id > 0 then return id end
      end
    end
  end
  return nil
end

local function Entry(questID)
  local e = ns.db.learned[questID]
  if not e then
    local faction = ns.Value(UnitFactionGroup, "player")
    e = { faction = (faction == "Alliance" or faction == "Horde") and faction or nil }
    ns.db.learned[questID] = e
  end
  return e
end

---------------------------------------------------------------------------
-- (1.0.1) Follow-ups: a quest the same quest giver offers within FOLLOW_SECS
-- after you turned in quest P, and that it did not offer before, comes after
-- P. "sure" (2) when we saw that giver's offers before the turn-in and the
-- level stayed the same (a level up can unlock quests too), else "maybe" (1).
-- learned[Q].after = { [P] = 2 or 1 }
---------------------------------------------------------------------------
local FOLLOW_SECS = 30
local offeredBy = {}  -- session: [giverKey] = { [questID] = true } offered so far
local lastTurnIn      -- { id, key, t, level, before = copy of offeredBy[key] or nil }

local function GiverKey(here)
  if type(here) ~= "table" then return nil end
  if here.npcID then return "c" .. here.npcID end
  if here.objID then return "o" .. here.objID end
  return nil
end

local function NoteFollowUp(questID, key)
  local t = lastTurnIn
  if not (t and key and t.key == key and t.id ~= questID) then return end
  if Clock() - t.t > FOLLOW_SECS then lastTurnIn = nil return end
  if t.before and t.before[questID] then return end
  local level = PlayerLevel()
  local sure = t.before ~= nil and level ~= nil and level == t.level
  local e = Entry(questID)
  e.after = type(e.after) == "table" and e.after or {}
  local v = sure and 2 or 1
  if (e.after[t.id] or 0) < v then e.after[t.id] = v end
end

-- Remember a quest start the first time an NPC offers it (accepted or not).
local function NoteOffered(questID, title, level, here)
  questID, level = ns.Num(questID), ns.Num(level)
  if not (questID and questID > 0) then return end
  local e = Entry(questID)
  if type(title) == "string" and ns.Usable(title) and title ~= "" then e.title = e.title or title end
  if level and level > 0 then e.level = e.level or level end
  here = here or Here()
  if not e.start then
    if here and here.npc then e.start = here end
  end
  local key = GiverKey(here)
  if key then
    NoteFollowUp(questID, key)
    offeredBy[key] = offeredBy[key] or {}
    offeredBy[key][questID] = true
  end
end

ns.On("QUEST_DETAIL", function()
  if not ns.db.learnQuests then return end
  local id = ns.Num(ns.Value(GetQuestID))
  if not id or id == 0 then return end
  local here = Here()
  if here then
    here.item = here.npc == nil or nil -- no NPC: started from an item
    if here.item then here.itemID = StartItem(id) end -- (1.0.1)
    pendingStart[id] = here
  end
  NoteOffered(id, ns.Value(GetTitleText), nil, here)
end)

-- Quests an NPC offers in its dialog, even the ones you do not take.
ns.On("GOSSIP_SHOW", function()
  if not ns.db.learnQuests or not (C_GossipInfo and C_GossipInfo.GetAvailableQuests) then return end
  local here = Here()
  for _, q in ipairs(ns.Value(C_GossipInfo.GetAvailableQuests) or {}) do
    NoteOffered(q.questID, q.title, q.questLevel, here)
  end
  local key = GiverKey(here) -- (1.0.1) an NPC without offers was seen too
  if key then offeredBy[key] = offeredBy[key] or {} end
end)
ns.On("QUEST_GREETING", function()
  if not ns.db.learnQuests or not GetNumAvailableQuests then return end
  local here = Here()
  local key = GiverKey(here)
  if key then offeredBy[key] = offeredBy[key] or {} end
  for i = 1, ns.Num(ns.Value(GetNumAvailableQuests)) or 0 do
    local questID = GetAvailableQuestInfo and select(6, pcall(GetAvailableQuestInfo, i))
    local title = ns.Value(GetAvailableTitle, i)
    -- (1.26) no ID in the greeting: the title of a known quest of this NPC
    if not (ns.Num(questID) and questID > 0) and ns.MatchOfferedTitle then questID = ns.MatchOfferedTitle(NpcID(), title) end
    NoteOffered(questID, title, nil, here)
  end
end)

-- Blizzard's own quest line data for a map (if the Forever client provides it).
local harvested = {}
function ns.HarvestQuestLines(mapID)
  if not (ns.db.learnQuests and mapID and C_QuestLine and C_QuestLine.GetAvailableQuestLines) then return 0 end
  if not harvested[mapID] and C_QuestLine.RequestQuestLinesForMap then
    harvested[mapID] = true
    pcall(C_QuestLine.RequestQuestLinesForMap, mapID)
  end
  local ok, lines = pcall(C_QuestLine.GetAvailableQuestLines, mapID)
  if not ok or type(lines) ~= "table" then return 0 end
  local added = 0
  for _, info in ipairs(lines) do
    local id = info.questID
    -- (1.23) a secret "hidden" flag counts as hidden (skipped, as before), without a boolean test on it
    local hidden = info.isHidden ~= nil and (not ns.Usable(info.isHidden) or info.isHidden ~= false)
    -- (1.26) a quest line step in progress is no quest start (unreadable counts as in progress)
    local progress = info.inProgress ~= nil and (not ns.Usable(info.inProgress) or info.inProgress ~= false)
    if ns.Num(id) and id > 0 and ns.Num(info.x) and ns.Num(info.y) and not hidden and not progress then
      local e = Entry(id)
      local name = info.questName
      if type(name) == "string" and ns.Usable(name) and name ~= "" then e.title = e.title or name end
      if not e.start then
        e.start = { map = mapID, x = info.x, y = info.y, source = "blizzard" }
        added = added + 1
      end
    end
  end
  return added
end

ns.On("QUEST_ACCEPTED", function(_, questID)
  questID = ns.Num(questID) -- (1.23) a secret ID must not become a table key
  if not ns.db.learnQuests or not questID or questID <= 0 then return end
  local e = Entry(questID)
  local title = ns.Value(C_QuestLog.GetTitleForQuestID, questID)
  if type(title) == "string" and title ~= "" then e.title = title end
  local index = ns.Num(ns.Value(C_QuestLog.GetLogIndexForQuestID, questID))
  local info = index and ns.Value(C_QuestLog.GetInfo, index)
  if type(info) == "table" and ns.Num(info.level) then e.level = info.level end
  local p = pendingStart[questID]
  if p then
    -- Never replace a known quest giver with a start without one (item, shared quest).
    if not (p.item and e.start and not e.start.item) then e.start = p end
    pendingStart[questID] = nil
  end
  if ns.QueuePinRefresh then ns.QueuePinRefresh() end -- (1.23) batched, not forced
end)

local function NoteFinish()
  if not ns.db.learnQuests then return end
  local id = ns.Num(ns.Value(GetQuestID))
  if id and id > 0 then
    local here = Here()
    if here then here.level = PlayerLevel() end -- level before the reward XP
    pendingFinish[id] = here
  end
end
ns.On("QUEST_PROGRESS", NoteFinish)
ns.On("QUEST_COMPLETE", NoteFinish)

ns.On("QUEST_TURNED_IN", function(_, questID)
  questID = ns.Num(questID) -- (1.23) a secret ID must not become a table key
  if not ns.db.learnQuests or not questID or questID <= 0 then return end
  local p = pendingFinish[questID]
  if p then
    local e = Entry(questID)
    local key = GiverKey(p)
    if key then
      local before
      if offeredBy[key] then
        before = {}
        for id in pairs(offeredBy[key]) do before[id] = true end
      end
      lastTurnIn = { id = questID, key = key, t = Clock(), level = p.level, before = before }
    end
    p.level = nil
    e.finish = p
    pendingFinish[questID] = nil
  end
  if ns.QueuePinRefresh then ns.QueuePinRefresh() end -- (1.23) batched, not forced
end)

---------------------------------------------------------------------------
-- Learning objective spots: where an objective counter went up
-- (account wide, max 30 spots per objective, at least ~2% of the map apart)
---------------------------------------------------------------------------
local MAX_SPOTS, MIN_DIST = 60, 0.02 -- (1.2) 60 spots per objective (was 30): sightings add more
local progress = {} -- [questID] = { [index] = numFulfilled }
local progressReady = false

-- Remember a spot (0-1) for an objective. true if it was new.
function ns.AddObjectiveSpot(questID, index, map, x, y)
  if not (map and x and y) then return false end
  ns.db.learnedObj = ns.db.learnedObj or {}
  local q = ns.db.learnedObj[questID] or {}
  ns.db.learnedObj[questID] = q
  local spots = q[index] or {}
  q[index] = spots
  for i = 1, #spots, 3 do
    if spots[i] == map and math.abs(spots[i + 1] - x) < MIN_DIST and math.abs(spots[i + 2] - y) < MIN_DIST then
      return false
    end
  end
  if #spots >= MAX_SPOTS * 3 then
    table.remove(spots, 1) table.remove(spots, 1) table.remove(spots, 1)
  end
  spots[#spots + 1] = map
  spots[#spots + 1] = math.floor(x * 1000 + 0.5) / 1000
  spots[#spots + 1] = math.floor(y * 1000 + 0.5) / 1000
  return true
end

local function AddSpot(questID, index)
  ns.AddObjectiveSpot(questID, index, ns.PlayerPosition())
end

---------------------------------------------------------------------------
-- (1.2) Sightings: a mob of an open objective whose nameplate shows up close
-- to you (within about 28 yards, the follow distance) marks your spot as a
-- place where it is. Out of combat, at most once per creature every 5
-- seconds; the 0.02 spacing of the spots keeps them apart. These spots are
-- shared like the others (Exchange.lua), so the map fills while people play.
---------------------------------------------------------------------------
local SIGHT_SECS = 5
local lastSight = {}
local sightStats = { seen = 0, added = 0, far = 0 }
function ns.SightingStats() return sightStats end
local function Close(unit)
  if not CheckInteractDistance then return false end
  local ok, near = pcall(CheckInteractDistance, unit, 4)
  return ok and ns.Usable(near) and near and true or false
end
-- Nameplates appear at about 40 yards: the visible ones are looked at again
-- every 2 seconds out of combat (cheap: a lookup per plate).
local function CheckPlates()
  if not (ns.db and ns.db.learnQuests and ns.NameplateUnits) or (InCombatLockdown and InCombatLockdown()) then return end
  for _, unit in ipairs(ns.NameplateUnits()) do
    local guid = ns.Value(UnitGUID, unit)
    if guid ~= nil then ns.NoteSighting(unit, ns.CreatureIDFromGUID(guid)) end
  end
end
ns.OnInit(function() ns.NewTicker(2, CheckPlates) end)
ns.CheckSightings = CheckPlates

function ns.NoteSighting(unit, creatureID)
  if not (ns.db and ns.db.learnQuests and creatureID and ns.CreatureQuestIndex) then return end
  if InCombatLockdown and InCombatLockdown() then return end
  local now = Clock()
  if lastSight[creatureID] and now - lastSight[creatureID] < SIGHT_SECS then return end
  local objectives = ns.CreatureQuestIndex(creatureID)
  if not objectives then return end
  local open = {}
  for _, entry in ipairs(objectives) do
    local questID, index = ns.ObjectiveEntry(entry)
    -- not for "use an item here" objectives: their learned spots are the place of use
    if ns.InQuestLog(questID) and not ns.IsQuestComplete(questID) and not ns.IsUseObjective(questID, index) then
      local o = ns.ClientObjectives(questID)[index]
      if not (type(o) == "table" and ns.True(o.finished)) then open[#open + 1] = { questID, index } end
    end
  end
  if #open == 0 then return end
  if not Close(unit) then sightStats.far = sightStats.far + 1 return end -- checked again later (slow ticker)
  lastSight[creatureID] = now
  sightStats.seen = sightStats.seen + 1
  local map, x, y = ns.PlayerPosition()
  for _, e in ipairs(open) do
    if ns.AddObjectiveSpot(e[1], e[2], map, x, y) then sightStats.added = sightStats.added + 1 end
  end
end

---------------------------------------------------------------------------
-- (1.0.1) What gave the credit: the creature you just killed (dead target),
-- the creature or object you just looted (quest items, LOOT_READY with
-- GetLootSourceInfo), the object you face (soft interact). Account wide:
--   learnedCredit[questID][index] = { c = { [creatureID] = n }, o = { [objectID] = n }, i = { [itemID] = n } }
--   learnedDrops[itemID] = { [ "c123" | "o45" ] = { n, map, x, y } }  where a quest item dropped
--   learnedItemStarts[itemID] = questID  item that starts a quest (from the loot window)
---------------------------------------------------------------------------
local LOOT_SECS, MAX_SOURCES = 5, 20
local lastLoot -- { t, sources = { {kind, id} }, items = { [itemID] = true } }

local function Bump(t, k)
  t[k] = math.min((t[k] or 0) + 1, 9999)
end

local function NoteCredit(questID, index, o)
  local db = ns.db
  db.learnedCredit = type(db.learnedCredit) == "table" and db.learnedCredit or {}
  local credit = {}
  local otype = type(o) == "table" and o.type ~= nil and ns.Usable(o.type) and o.type or nil
  if otype ~= "item" then
    -- killed: the target is dead right now
    local kind, id = UnitKindID("target")
    if kind == "c" and ns.True(ns.Value(UnitIsDead, "target")) then credit[#credit + 1] = { "c", id } end
  end
  if otype ~= "monster" and lastLoot and Clock() - lastLoot.t <= LOOT_SECS then
    for _, src in ipairs(lastLoot.sources) do credit[#credit + 1] = src end
    for itemID in pairs(lastLoot.items) do credit[#credit + 1] = { "i", itemID } end
  end
  if #credit == 0 and otype ~= "monster" then
    local kind, id = UnitKindID("softinteract")
    if kind == "o" then credit[1] = { "o", id } end
  end
  if #credit == 0 then return end
  local q = db.learnedCredit[questID] or {}
  db.learnedCredit[questID] = q
  local c = q[index] or {}
  q[index] = c
  local newCreature = false
  for _, src in ipairs(credit) do
    c[src[1]] = c[src[1]] or {}
    if src[1] == "c" and not c.c[src[2]] then newCreature = true end
    Bump(c[src[1]], src[2])
  end
  -- (1.2) a mob newly known to count for this objective: nameplates, tooltips,
  -- sightings and the map use it from now on
  if newCreature and ns.ResetCreatureIndex then ns.ResetCreatureIndex() end
end

-- (1.2) Creatures that gave credit for an objective (learned), { ids } or nil.
-- A creature counts once it gave credit twice, or once when the data names no
-- creature for that objective (new Forever quests).
function ns.LearnedObjectiveCreatures(questID, index, dataHasCreatures)
  local q = type(ns.db.learnedCredit) == "table" and ns.db.learnedCredit[questID]
  local c = q and q[index] and q[index].c
  if type(c) ~= "table" then return nil end
  local list
  for id, n in pairs(c) do
    if type(id) == "number" and (n >= 2 or not dataHasCreatures) then
      list = list or {}
      list[#list + 1] = id
    end
  end
  if list then table.sort(list) end
  return list
end

local function ItemIDFromLink(link)
  if type(link) ~= "string" or not ns.Usable(link) then return nil end
  local id = tonumber(link:match("item:(%d+)"))
  return id and id > 0 and id or nil
end

ns.On("LOOT_READY", function()
  if not ns.db.learnQuests or not (GetNumLootItems and GetLootSlotInfo) then return end
  local db = ns.db
  local map, x, y = ns.PlayerPosition()
  local loot = { t = Clock(), sources = {}, items = {} }
  local seenSrc = {}
  for slot = 1, ns.Num(ns.Value(GetNumLootItems)) or 0 do
    local ok, _, _, _, _, _, _, isQuestItem, startsQuest = pcall(GetLootSlotInfo, slot)
    local itemID = ok and ns.True(isQuestItem) and ItemIDFromLink(ns.Value(GetLootSlotLink, slot))
    if itemID then
      startsQuest = ns.Num(startsQuest)
      if startsQuest and startsQuest > 0 then
        db.learnedItemStarts = type(db.learnedItemStarts) == "table" and db.learnedItemStarts or {}
        db.learnedItemStarts[itemID] = startsQuest
      else
        loot.items[itemID] = true -- may be what an objective counts
      end
      -- who dropped it (GUID, count pairs)
      local src = GetLootSourceInfo and { pcall(GetLootSourceInfo, slot) } or {}
      if src[1] then
        for i = 2, #src, 2 do
          local kind, id = ns.GUIDKindID(src[i])
          if kind then
            local key = kind .. id
            if not seenSrc[key] then
              seenSrc[key] = true
              loot.sources[#loot.sources + 1] = { kind, id }
            end
            db.learnedDrops = type(db.learnedDrops) == "table" and db.learnedDrops or {}
            local d = db.learnedDrops[itemID] or {}
            db.learnedDrops[itemID] = d
            if d[key] then
              d[key][1] = math.min(d[key][1] + 1, 9999)
            else
              local n = 0
              for _ in pairs(d) do n = n + 1 end
              if n < MAX_SOURCES then
                d[key] = { 1, map, map and math.floor(x * 1000 + 0.5) / 1000, map and math.floor(y * 1000 + 0.5) / 1000 }
              end
            end
          end
        end
      end
    end
  end
  if next(loot.items) then lastLoot = loot end
end)

local function ScanProgress()
  local seen = {}
  for _, info in ipairs(ns.QuestLogEntries()) do
    seen[info.questID] = true
    local id = info.questID
    local old = progress[id]
    local now = {}
    for index, o in ipairs(ns.ClientObjectives(id)) do
      now[index] = type(o) == "table" and ns.Num(o.numFulfilled) or 0
      if progressReady and ns.db.learnQuests and old and old[index] and now[index] > old[index] then
        AddSpot(id, index)
        NoteCredit(id, index, o)
      end
    end
    progress[id] = now
  end
  -- abandoned or turned in: forget the counters, a retaken quest starts at 0
  for id in pairs(progress) do
    if not seen[id] then progress[id] = nil end
  end
end

-- (1.23) Batched with the quest displays (Core.lua): the quest log is read once.
ns.RegisterRefresh("learn", ScanProgress)
ns.On("QUEST_LOG_UPDATE", function() ns.QueueRefresh("learn") end)
ns.On("PLAYER_ENTERING_WORLD", function()
  ScanProgress()
  progressReady = true
end)

---------------------------------------------------------------------------
-- Does Questie know this quest? (QuestieDB public API, contract 2)
---------------------------------------------------------------------------
local questieCache = {}
function ns.QuestieKnows(questID)
  local db = LibQuestieDB
  if type(db) ~= "table" or not db.Quest or not db.Quest.GetAll then return nil end
  if questieCache[questID] ~= nil then return questieCache[questID] end
  local ok, fits = pcall(db.RequireContract, 2)
  if not (ok and fits) then return nil end
  local ok2, values = pcall(db.Quest.GetAll, questID, { "name" })
  local known = ok2 and type(values) == "table" and values[1] ~= nil
  questieCache[questID] = known
  return known
end
