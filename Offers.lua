local _, ns = ...

---------------------------------------------------------------------------
-- (1.24) Is a quest really available? The bundled data (All The Things) has
-- no minimum level for 331 quests and misses some prerequisites, so Questdon
-- showed quests that the quest giver does not offer yet (Nature's Call in
-- Teldrassil, a Forever quest without a level in the data). Ground truth
-- from the client comes first:
--
--   1. The client's quest lines of a map (C_QuestLine.GetAvailableQuestLines
--      after RequestQuestLinesForMap, refreshed on QUESTLINE_UPDATE): a listed
--      quest is available. A quest of a quest line the client knows but does
--      not list now (C_QuestLine.GetQuestLineQuests / GetQuestLineInfo) is
--      "not yet". Quests without a known quest line: no answer, the data
--      decides. An empty list is no answer either (the API may not know the
--      classic quests at all).
--   2. What quest givers offer this character (GOSSIP_SHOW, QUEST_GREETING):
--      a data quest of that NPC that the data calls available now, but that
--      the NPC does not offer, is "not offered at level L" (per character,
--      saved) and hidden until the character's level rises. Talking to the
--      NPC again judges again. An offered quest is confirmed (per character;
--      account wide the lowest level it was offered at, learned[id].offeredAt).
--
-- Unreadable values (secret NPC GUID, secret or missing quest IDs) never
-- judge anything. Nothing here touches Blizzard frames or Lua state.
---------------------------------------------------------------------------
local stats = { dialogs = 0, secretNpc = 0, unreadable = 0, judged = 0, notOffered = 0, confirmed = 0, clientReads = 0,
  objects = 0, deferred = 0, multiGiver = 0, expired = 0, titles = 0, cleared = 0 }

-- (1.26) A "not offered" verdict never hides a quest for good (data errors):
-- it ends with a level up, a quest turned in at that NPC or near the place
-- of the verdict, or after EXPIRE seconds. A dialog within GRACE seconds after
-- a turn-in at the same NPC only confirms (the follow-up may come a moment
-- later). NEAR_TURNIN: yards around the place of the verdict.
local EXPIRE, GRACE, NEAR_TURNIN = 30 * 60, 3, 100

-- Per character store (SavedVariablesPerCharacter QuestdonCharDB, see Core.lua).
local session = {}
local function Char()
  local c = ns.charDB
  if type(c) ~= "table" then c = session end
  if type(c.notOffered) ~= "table" then c.notOffered = {} end -- [questID] = player level when not offered
  if type(c.offered) ~= "table" then c.offered = {} end       -- [questID] = player level when offered
  -- (1.26) [questID] = { t = time, npc = creatureID, map, x, y } of the verdict
  if type(c.notOfferedInfo) ~= "table" then c.notOfferedInfo = {} end
  return c
end
ns.OfferStore = Char

-- Seconds; real time when the client has it (survives /reload and relog),
-- else the session clock (a clock that went backwards ends a verdict).
local function Clock()
  return ns.Num(ns.Value(time)) or ns.Num(ns.Value(GetTime)) or 0
end
ns.OfferClock = Clock

local function Drop(c, questID)
  c.notOffered[questID], c.notOfferedInfo[questID] = nil, nil
end

---------------------------------------------------------------------------
-- 2. Quest givers
---------------------------------------------------------------------------
-- Level at which the quest giver did not offer the quest, while that still
-- holds (the character's level has not risen since, not older than EXPIRE),
-- else nil. An unknown (secret) player level keeps the mark.
function ns.NotOfferedLevel(questID, level)
  local c = Char()
  local at = c.notOffered[questID]
  if not at then return nil end
  level = level or ns.PlayerLevel()
  if level and level > at then
    Drop(c, questID) -- level up: show it again
    return nil
  end
  local info = c.notOfferedInfo[questID]
  local now = Clock()
  if type(info) ~= "table" or not ns.Num(info.t) then
    -- a verdict from 1.24/1.25 (no time): the clock starts now
    info = type(info) == "table" and info or {}
    info.t = now
    c.notOfferedInfo[questID] = info
  end
  if now - info.t >= EXPIRE or now < info.t then
    Drop(c, questID)
    stats.expired = stats.expired + 1
    return nil
  end
  return at
end

-- Offered to this character (any level) or, account wide, at or below its level.
function ns.OfferConfirmed(questID, level)
  if Char().offered[questID] then return true end
  local e = ns.db and ns.db.learned and ns.db.learned[questID]
  local at = e and ns.Num(e.offeredAt)
  level = level or ns.PlayerLevel()
  return at ~= nil and level ~= nil and level >= at
end

local function Confirm(questID, level)
  local c = Char()
  if not c.offered[questID] then stats.confirmed = stats.confirmed + 1 end
  c.offered[questID] = level or c.offered[questID] or 0
  Drop(c, questID)
  local e = ns.db and ns.db.learned and ns.db.learned[questID]
  if e and level and (not ns.Num(e.offeredAt) or level < e.offeredAt) then e.offeredAt = level end
end

-- (1.26) Who opened the dialog: "npc" (creature, with its ID), "object" (a
-- game object: a wanted poster, a book), "player" (a group member sharing a
-- quest), "none" (no unit: a quest started from an item) or "secret"
-- (unreadable GUID: nothing is judged, nothing confirmed).
local function Source()
  if UnitGUID == nil then return "none" end
  local ok, guid = pcall(UnitGUID, "npc")
  if not ok then return "secret" end
  if guid == nil then return "none" end
  if not ns.Usable(guid) or type(guid) ~= "string" then return "secret" end
  local kind = guid:match("^(%a+)%-")
  if kind == "Creature" or kind == "Vehicle" then
    local id = ns.CreatureIDFromGUID and ns.CreatureIDFromGUID(guid)
    if id then return "npc", id end
    return "secret"
  end
  if kind == "GameObject" then return "object" end
  if kind == "Player" or kind == "Pet" then return "player" end
  return "none"
end
ns.OfferSource = Source

-- Grey (trivial) quests may be filtered out of the dialog by the client:
-- their absence says nothing. (1.26) The client's own answer counts first
-- (a secret one as grey), then the quest level against the trivial range.
local function Trivial(questID)
  if C_QuestLog and type(C_QuestLog.IsQuestTrivial) == "function" then
    local ok, v = pcall(C_QuestLog.IsQuestTrivial, questID)
    if ok and v ~= nil then
      if not ns.Usable(v) then return true end
      if v == true then return true end
    end
  end
  local lv = ns.QuestMinLevel(questID) or ns.QuestLevel(questID)
  return lv ~= nil and ns.LevelColor and ns.LevelColor(lv) == "|cff808080"
end

-- (1.26) Data quests of this NPC: its quests in the data plus quests learned
-- at it that the data does not know.
local function GiverQuests(npcID)
  local list = {}
  local gives = ns.CreatureQuestIndex and select(2, ns.CreatureQuestIndex(npcID))
  for _, id in ipairs(gives or {}) do list[#list + 1] = id end
  for id, e in pairs(ns.db.learned or {}) do
    if type(e) == "table" and type(e.start) == "table" and e.start.npcID == npcID and not (ns.ATT_QUESTS and ns.ATT_QUESTS[id]) then
      list[#list + 1] = id
    end
  end
  return list
end
ns.GiverQuests = GiverQuests

-- (1.26) Greeting dialogs may give titles without quest IDs: match the title
-- against the data quests of this NPC. Localised titles only: the client's
-- title (when cached), the title Questdon learned from the client, and the
-- data's name on English clients (the data's names are English). Exactly one
-- quest must match, else nil.
local function Norm(s)
  if type(s) ~= "string" or not ns.Usable(s) then return nil end
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
  return s ~= "" and s or nil
end
local function English()
  local loc = ns.Value(GetLocale)
  return loc == "enUS" or loc == "enGB"
end
function ns.MatchOfferedTitle(npcID, title)
  title = Norm(title)
  if not (title and npcID) then return nil end
  local found
  for _, id in ipairs(GiverQuests(npcID)) do
    local names = { ns.Value(C_QuestLog.GetTitleForQuestID, id) }
    local e = ns.db.learned and ns.db.learned[id]
    if type(e) == "table" then names[#names + 1] = e.title end
    if English() and ns.DataQuestName then names[#names + 1] = ns.DataQuestName(id) end
    for _, n in ipairs(names) do
      if Norm(n) == title then
        if found and found ~= id then return nil end -- two quests with that title: no answer
        found = id
      end
    end
  end
  if found then stats.titles = stats.titles + 1 end
  return found
end

local function GiverCount(questID)
  local g = ns.QuestGiverIDs and ns.QuestGiverIDs(questID)
  return type(g) == "table" and #g or 0
end

-- Last turn-in per NPC (GRACE) and the NPC of the open turn-in dialog.
local turnedInAt = {} -- [npcID] = Clock()
local finishNpc       -- creature ID of the last QUEST_PROGRESS / QUEST_COMPLETE

-- offered: { [questID] = true }; complete: every offered quest was readable;
-- turnInOpen: the dialog lists a quest ready to turn in (or unreadable).
local function Judge(npcID, offered, complete, turnInOpen)
  local level = ns.PlayerLevel()
  for id in pairs(offered) do
    Confirm(id, level)
    if ns.NoteOfferedHere then ns.NoteOfferedHere(id, npcID) end -- (1.1) it exists
  end
  if not (complete and npcID and level) then return end
  -- (1.26) before a turn-in (or right after one) the follow-up is not there
  -- yet: confirm only
  local t = turnedInAt[npcID]
  local now = Clock()
  if turnInOpen or (t and now - t < GRACE and now >= t) then
    stats.deferred = stats.deferred + 1
    if ns.QueuePinRefresh then ns.QueuePinRefresh() end
    return
  end
  stats.judged = stats.judged + 1
  local c = Char()
  local m, x, y = ns.PlayerPosition()
  local function Check(id)
    if offered[id] then return end
    if ns.IsQuestDone(id) or ns.InQuestLog(id) or ns.QuestKnownMissing(id) then return end
    -- only where the data says "available now": prerequisites the data knows
    -- are done, so the NPC's answer is news (a later prerequisite done at the
    -- same level must not stay hidden)
    if not ns.DataCanTakeQuest(id) or Trivial(id) then return end
    -- (1.26) several givers in the data: another one may offer it
    if GiverCount(id) > 1 then stats.multiGiver = stats.multiGiver + 1 return end
    if c.notOffered[id] ~= level then stats.notOffered = stats.notOffered + 1 end
    -- (1.1) account wide: after 3 different levels it is hidden (NotHere.lua)
    if ns.NoteNotOffered then ns.NoteNotOffered(id, npcID, level) end
    c.notOffered[id] = level
    c.notOfferedInfo[id] = { t = now, npc = npcID, map = m, x = x, y = y }
    c.offered[id] = nil
  end
  for _, id in ipairs(GiverQuests(npcID)) do Check(id) end
  if ns.QueuePinRefresh then ns.QueuePinRefresh() end
  if ns.QueueRefresh then ns.QueueRefresh("panel") end
end

-- read(npcID) returns offered, complete, turnInOpen.
local function Dialog(read)
  stats.dialogs = stats.dialogs + 1
  local kind, npcID = Source()
  if kind == "secret" then stats.secretNpc = stats.secretNpc + 1 return end
  -- a group member, or no unit at all: says nothing about quest givers
  if kind == "player" or kind == "none" then return end
  local offered, complete, turnInOpen = read(npcID)
  if not offered then stats.unreadable = stats.unreadable + 1 return end
  if not complete then stats.unreadable = stats.unreadable + 1 end
  if kind ~= "npc" then
    -- objects and items: what they offer is offered, nothing else is judged
    stats.objects = stats.objects + 1
    npcID = nil
  end
  Judge(npcID, offered, complete, turnInOpen)
end

-- A readable false only; true or unreadable counts as "ready to turn in".
local function Ready(v)
  return v ~= nil and (not ns.Usable(v) or v ~= false)
end

ns.On("GOSSIP_SHOW", function()
  if not (C_GossipInfo and type(C_GossipInfo.GetAvailableQuests) == "function") then return end
  Dialog(function(npcID)
    local list = ns.Value(C_GossipInfo.GetAvailableQuests)
    if type(list) ~= "table" then return nil end
    local offered, complete = {}, true
    for _, q in ipairs(list) do
      local id = type(q) == "table" and ns.Num(q.questID)
      if (not id or id <= 0) and type(q) == "table" then id = ns.MatchOfferedTitle(npcID, q.title) end
      if id and id > 0 then offered[id] = true else complete = false end
    end
    local turnIn = false
    local active = type(C_GossipInfo.GetActiveQuests) == "function" and ns.Value(C_GossipInfo.GetActiveQuests)
    if type(active) == "table" then
      for _, q in ipairs(active) do
        if type(q) ~= "table" or Ready(q.isComplete) then turnIn = true end
      end
    elseif type(C_GossipInfo.GetActiveQuests) == "function" then
      turnIn = true -- unreadable list
    end
    return offered, complete, turnIn
  end)
end)

ns.On("QUEST_GREETING", function()
  if type(GetNumAvailableQuests) ~= "function" then return end
  Dialog(function(npcID)
    local n = ns.Num(ns.Value(GetNumAvailableQuests))
    if not n then return nil end
    local offered, complete = {}, true
    for i = 1, n do
      local id
      if type(GetAvailableQuestInfo) == "function" then
        -- isTrivial, frequency, isRepeatable, isLegendary, questID, ...
        local ok, _, _, _, _, questID = pcall(GetAvailableQuestInfo, i)
        id = ok and ns.Num(questID) or nil
      end
      if not id or id <= 0 then id = ns.MatchOfferedTitle(npcID, ns.Value(GetAvailableTitle, i)) end
      if id and id > 0 then offered[id] = true else complete = false end
    end
    local turnIn = false
    local na = type(GetNumActiveQuests) == "function" and ns.Num(ns.Value(GetNumActiveQuests))
    if type(GetNumActiveQuests) == "function" and not na then turnIn = true end
    for i = 1, na or 0 do
      local ok, _, isComplete = pcall(GetActiveTitle, i)
      if not ok or Ready(isComplete) then turnIn = true end
    end
    return offered, complete, turnIn
  end)
end)

-- A quest shown in the quest dialog is offered (never judges the others: the
-- dialog also opens after choosing one quest from a list). (1.26) Also from
-- objects, from items (questStartItemID) and quests the client accepts by
-- itself; never from a group member (shared quest) or an unreadable source.
ns.On("QUEST_DETAIL", function(_, questStartItemID)
  local id = ns.Num(ns.Value(GetQuestID))
  if not id or id <= 0 then return end
  local kind = Source()
  local item = ns.Num(questStartItemID)
  local auto = type(QuestGetAutoAccept) == "function" and ns.True(ns.Value(QuestGetAutoAccept))
  if kind == "npc" or kind == "object" or (kind == "none" and ((item and item > 0) or auto)) then
    Confirm(id, ns.PlayerLevel())
    if ns.NoteOfferedHere then ns.NoteOfferedHere(id, kind == "npc" and select(2, Source()) or nil) end -- (1.1)
  end
end)

ns.On("QUEST_ACCEPTED", function(_, a, b)
  local id = ns.Num(b) or ns.Num(a)
  if id and id > 0 and Char().notOffered[id] then Drop(Char(), id) end
end)

-- (1.26) Turn-ins: remember the NPC (GRACE) and forget the verdicts made at
-- it, near the player, or about the follow-ups of the quest. The next dialog
-- judges again.
local function NoteFinishNpc()
  local kind, npcID = Source()
  finishNpc = kind == "npc" and npcID or nil
end
ns.On("QUEST_PROGRESS", NoteFinishNpc)
ns.On("QUEST_COMPLETE", NoteFinishNpc)

local function Near(info, pc, pn, pw)
  if not (pc and ns.WorldPos and info.map and info.x and info.y) then return false end
  local c, n, w = ns.WorldPos(info.map, info.x, info.y)
  return c == pc and (n - pn) ^ 2 + (w - pw) ^ 2 <= NEAR_TURNIN * NEAR_TURNIN
end

ns.On("QUEST_TURNED_IN", function(_, questID)
  questID = ns.Num(questID)
  local kind, npcID = Source()
  npcID = (kind == "npc" and npcID) or finishNpc
  finishNpc = nil
  if npcID then turnedInAt[npcID] = Clock() end
  if npcID and ns.NotHereTurnIn then ns.NotHereTurnIn(npcID) end -- (1.1) count the levels again
  local follow = {}
  if questID and ns.FollowUpQuests then
    for _, id in ipairs(ns.FollowUpQuests(questID)) do follow[id] = true end
  end
  local c = Char()
  local pc, pn, pw
  if ns.PlayerWorld then pc, pn, pw = ns.PlayerWorld() end
  local any = false
  for id in pairs(c.notOffered) do
    local info = c.notOfferedInfo[id]
    if follow[id] or (type(info) == "table" and ((npcID and info.npc == npcID) or Near(info, pc, pn, pw))) then
      Drop(c, id)
      stats.cleared = stats.cleared + 1
      any = true
    end
  end
  if any and ns.QueuePinRefresh then ns.QueuePinRefresh() end
end)

-- Expired verdicts leave the map without waiting for another event.
ns.OnInit(function()
  ns.NewTicker(60, function()
    local c, any = Char(), false
    for id in pairs(c.notOffered) do
      if not ns.NotOfferedLevel(id) then any = true end
    end
    if any and ns.QueuePinRefresh then ns.QueuePinRefresh() end
  end)
end)

---------------------------------------------------------------------------
-- 1. The client's quest lines
---------------------------------------------------------------------------
local lines = {}     -- [mapID] = entry or false (no answer), this session
local requested = {} -- [mapID] = Clock() of the request
local lineOf = {}    -- [questID] = true/false: belongs to a quest line (static)
local lineStats = { inProgress = 0, offMap = 0, notDrawn = 0, forced = 0, rerequests = 0 }

local function HasAPI()
  return C_QuestLine ~= nil and type(C_QuestLine.GetAvailableQuestLines) == "function"
end
ns.ClientQuestLinesAPI = HasAPI

local function Request(mapID)
  if requested[mapID] or type(C_QuestLine.RequestQuestLinesForMap) ~= "function" then return end
  requested[mapID] = Clock()
  pcall(C_QuestLine.RequestQuestLinesForMap, mapID)
end

-- (1.26) QuestLineInfo flags (wow-ui-source, branch forever): nil = field
-- missing (counts as false, as in older clients), "secret" = unreadable.
local function Flag(v)
  if v == nil then return false end
  if not ns.Usable(v) then return "secret" end
  return v == true
end

-- Tracking switches of the minimap (C_Minimap); unknown counts as off.
local function Tracking(fn)
  return C_Minimap ~= nil and ns.True(ns.Value(C_Minimap[fn]))
end

-- Is child (a uiMapID) mapID itself or one of its sub maps?
local function OnMap(child, mapID)
  for _ = 1, 8 do
    if not child or child == 0 then return false end
    if child == mapID then return true end
    local info = C_Map and ns.Value(C_Map.GetMapInfo, child)
    child = type(info) == "table" and ns.Num(info.parentMapID) or nil
  end
  return false
end

-- One QuestLineInfo into the entry. As Blizzard's QuestOfferDataProvider:
-- inProgress = no offer; startMapID must be this map or a sub map; the game
-- draws its "!" only for offers that are not hidden (trivial; unless the
-- minimap tracks hidden quests), not a local story, and not account
-- completed (unless tracked). A secret flag: not available / not drawn.
local function AddInfo(e, info, mapID)
  if type(info) ~= "table" or not ns.Usable(info) then return end
  local id = ns.Num(info.questID)
  local line = ns.Num(info.questLineID)
  if line and line > 0 and type(C_QuestLine.GetQuestLineQuests) == "function" and not e.lineRead[line] then
    e.lineRead[line] = true
    local ok2, quests = pcall(C_QuestLine.GetQuestLineQuests, line)
    if ok2 and type(quests) == "table" and ns.Usable(quests) then
      for _, q in ipairs(quests) do
        q = ns.Num(q)
        if q then e.member[q] = true lineOf[q] = true end
      end
    end
  end
  if not (id and id > 0) then return end
  e.member[id] = true
  if Flag(info.inProgress) ~= false then lineStats.inProgress = lineStats.inProgress + 1 return end
  if not e.available[id] then e.count = e.count + 1 end
  e.available[id] = true
  local start = ns.Num(info.startMapID)
  if start and start > 0 and not OnMap(start, mapID) then lineStats.offMap = lineStats.offMap + 1 return end
  local x, y = ns.Num(info.x), ns.Num(info.y)
  if not (x and y and x > 0 and y > 0) then return end
  e.pos[id] = { x, y }
  local hidden, story, account = Flag(info.isHidden), Flag(info.isLocalStory), Flag(info.isAccountCompleted)
  if hidden == true then e.trivial[id] = true end
  local drawn = (hidden == false or (hidden == true and Tracking("IsTrackingHiddenQuests")))
    and story == false
    and (account == false or (account == true and Tracking("IsTrackingAccountCompletedQuests")))
  if drawn then e.drawn[id] = true else lineStats.notDrawn = lineStats.notDrawn + 1 end
end

local function Read(mapID)
  stats.clientReads = stats.clientReads + 1
  local ok, list = pcall(C_QuestLine.GetAvailableQuestLines, mapID)
  if not ok or type(list) ~= "table" or not ns.Usable(list) then return false end
  local e = { available = {}, member = {}, pos = {}, drawn = {}, trivial = {}, lineRead = {}, count = 0 }
  for _, info in ipairs(list) do AddInfo(e, info, mapID) end
  -- (1.26) quests the client forces visible on this map (GetQuestLineInfo each)
  if type(C_QuestLine.GetForceVisibleQuests) == "function" and type(C_QuestLine.GetQuestLineInfo) == "function" then
    local okF, forced = pcall(C_QuestLine.GetForceVisibleQuests, mapID)
    if okF and type(forced) == "table" and ns.Usable(forced) then
      for _, q in ipairs(forced) do
        q = ns.Num(q)
        if q and q > 0 and not e.available[q] then
          local okI, info = pcall(C_QuestLine.GetQuestLineInfo, q, mapID)
          if okI then
            local before = e.count
            AddInfo(e, info, mapID)
            if e.count > before then lineStats.forced = lineStats.forced + 1 end
          end
        end
      end
    end
  end
  e.lineRead = nil
  if e.count == 0 then return false end
  return e
end

-- The client's list for a map (asks for it the first time): entry or nil.
-- entry.available[questID], entry.pos[questID] = { x, y } (0-1),
-- (1.26) entry.drawn[questID]: the game draws its own "!" there.
function ns.ClientQuestLines(mapID)
  mapID = ns.Num(mapID)
  if not mapID or not HasAPI() then return nil end
  local e = lines[mapID]
  if e == nil then
    Request(mapID)
    e = Read(mapID)
    lines[mapID] = e
  end
  return e or nil
end

local function InSomeLine(questID, mapID)
  local v = lineOf[questID]
  if v ~= nil then return v end
  v = false
  if type(C_QuestLine.GetQuestLineInfo) == "function" then
    local ok, info = pcall(C_QuestLine.GetQuestLineInfo, questID, mapID)
    if ok and type(info) == "table" and ns.Usable(info) and (ns.Num(info.questLineID) or 0) > 0 then v = true end
  end
  lineOf[questID] = v
  return v
end

-- true: the client lists the quest as available; false: it belongs to a quest
-- line the client knows, but is not available yet; nil: the client says
-- nothing (no list for that map yet, or no quest line). Only reads lists
-- already asked for (never requests a map by itself). mapID: the quest's
-- start map if left out.
function ns.ClientAvailability(questID, mapID)
  if not HasAPI() then return nil end
  mapID = mapID or (ns.QuestStart and ns.QuestStart(questID))
  local e = mapID and lines[mapID]
  if not e then return nil end
  if e.available[questID] then return true end
  if e.member[questID] or InSomeLine(questID, mapID) then return false end
  return nil
end

-- "game" (the client lists it), "npc" (offered to this character or, at
-- this level, to the account), "database" (only the data says so).
function ns.AvailabilitySource(questID)
  if ns.ClientAvailability(questID) == true then return "game" end
  if ns.OfferConfirmed(questID) then return "npc" end
  return "database"
end

local function Forget()
  for k in pairs(lines) do lines[k] = nil end
end
-- (1.26) QUESTLINE_UPDATE(requestRequired): with true the client wants the
-- maps asked again (Blizzard's provider calls RequestQuestLinesForMap then).
-- A request younger than 2 seconds is still under way and is not repeated
-- (no request loop). Unreadable counts as true.
ns.On("QUESTLINE_UPDATE", function(_, requestRequired)
  if requestRequired ~= nil and (not ns.Usable(requestRequired) or requestRequired == true) then
    local now = Clock()
    for k, t in pairs(requested) do
      if now - t >= 2 or now < t then requested[k] = nil lineStats.rerequests = lineStats.rerequests + 1 end
    end
  end
  Forget()
  -- the world map and the minimap queue themselves on this event
  if ns.QueueRefresh then ns.QueueRefresh("panel", "nameplates") end
end)
local function ForgetAll()
  Forget()
  for k in pairs(requested) do requested[k] = nil end
end
ns.On("QUEST_TURNED_IN", ForgetAll)
ns.On("QUEST_ACCEPTED", ForgetAll)
ns.On("PLAYER_LEVEL_UP", function(_, level)
  ForgetAll()
  -- marks from lower levels are void now
  level = ns.Num(level)
  if level then
    local c = Char()
    for id, at in pairs(c.notOffered) do
      if level > at then Drop(c, id) end
    end
  end
end)

---------------------------------------------------------------------------
-- For /qd diag
---------------------------------------------------------------------------
function ns.AvailabilityState(mapID)
  local c = Char()
  local nOff, nNow, nConf = 0, 0, 0
  local level = ns.PlayerLevel()
  for _, at in pairs(c.notOffered) do
    nOff = nOff + 1
    if not level or level <= at then nNow = nNow + 1 end
  end
  for _ in pairs(c.offered) do nConf = nConf + 1 end
  local maps, listed = 0, 0
  for _, e in pairs(lines) do
    if e then maps = maps + 1 listed = listed + e.count end
  end
  local here = mapID and lines[mapID]
  local source = not HasAPI() and "database (no quest line API)"
    or here and "client quest lines + npc + database"
    or "npc + database (no client list for this map)"
  return ("source %s; client lists %d maps, %d quests, reads %d; givers: dialogs %d, judged %d, secret npc %d, unreadable %d; not offered %d (hidden now %d), confirmed %d"
    .. "; objects %d, deferred %d, several givers %d, titles matched %d, expired %d, cleared by turn-in %d"
    .. "; lines: in progress %d, other map %d, not drawn %d, forced %d, re-requests %d"):format(
    source, maps, listed, stats.clientReads, stats.dialogs, stats.judged, stats.secretNpc, stats.unreadable,
    nOff, nNow, nConf, stats.objects, stats.deferred, stats.multiGiver, stats.titles, stats.expired, stats.cleared,
    lineStats.inProgress, lineStats.offMap, lineStats.notDrawn, lineStats.forced, lineStats.rerequests)
end
