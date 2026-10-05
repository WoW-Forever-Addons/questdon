local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Quest data from three sources, best first:
--   1. what Questdon learned while playing (ns.db.learned)
--   2. All The Things' Forever database, bundled (Data/ATT_Quests.lua, MIT)
--   3. Questie, only to avoid drawing what Questie already draws
---------------------------------------------------------------------------
local Q = ns.ATT_QUESTS or {}
local OBJ = ns.ATT_OBJECTIVES or {}
local NPC = ns.ATT_CREATURES or {}

-- field positions in ns.ATT_QUESTS rows
local MAP, X, Y, FACTION, LEVEL, PREREQS, GIVERS, FLAGS, CLASSES, RACES, NEED, SKILL, NAME = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13

-- Quests by start map, built once.
local byMap
local function ByMap()
  if byMap then return byMap end
  byMap = {}
  for id, q in pairs(Q) do
    local m = q[MAP]
    if m and q[X] then
      byMap[m] = byMap[m] or {}
      table.insert(byMap[m], id)
    end
  end
  return byMap
end

-- Follow-up quests: [prereqID] = { questIDs }
local followUps
local function FollowUps()
  if followUps then return followUps end
  followUps = {}
  for id, q in pairs(Q) do
    for _, pre in ipairs(q[PREREQS] or {}) do
      followUps[pre] = followUps[pre] or {}
      table.insert(followUps[pre], id)
    end
  end
  return followUps
end

---------------------------------------------------------------------------
-- Player
---------------------------------------------------------------------------
-- Unknown (missing or secret) values stay nil and are not checked.
-- (1.23) Read once per scope (ns.SafeCall): this ran for every quest checked.
local function ReadPlayer()
  local faction = ns.Value(UnitFactionGroup, "player")
  local raceID = UnitRace and select(4, pcall(UnitRace, "player"))
  local classID = UnitClass and select(4, pcall(UnitClass, "player"))
  return {
    faction = faction == "Alliance" and "A" or faction == "Horde" and "H" or nil,
    race = ns.Num(raceID), class = ns.Num(classID), level = ns.PlayerLevel(),
  }
end
local function Player()
  return ns.ScopeValue("player", ReadPlayer)
end

local function Contains(list, value)
  for _, v in ipairs(list) do if v == value then return true end end
  return false
end

-- (1.23) Read once per scope (ns.SafeCall), see Core.lua.
local function ReadDone(questID) return ns.True(ns.Value(C_QuestLog.IsQuestFlaggedCompleted, questID)) end
function ns.IsQuestDone(questID)
  return ns.Memo("done", questID, ReadDone)
end

local function ReadInLog(questID) return (ns.Num(ns.Value(C_QuestLog.GetLogIndexForQuestID, questID)) or 0) > 0 end
function ns.InQuestLog(questID)
  return ns.Memo("inLog", questID, ReadInLog)
end

-- Could this character ever do the quest? (faction, race and class only)
local function Reachable(questID, player)
  local q = Q[questID]
  if not q then return true end -- unknown to ATT: no reason to rule it out
  if q[FACTION] and player.faction and q[FACTION] ~= player.faction then return false end
  if q[RACES] and player.race and not Contains(q[RACES], player.race) then return false end
  if q[CLASSES] and player.class and not Contains(q[CLASSES], player.class) then return false end
  return true
end

-- (1.0) Could this character ever do the quest? (public, see Reachable)
function ns.QuestReachable(questID)
  return Reachable(questID, Player())
end

-- (1.0) The quests ATT lists as providing or needing an item (nil if unknown).
function ns.QuestsForItem(itemID)
  local list = ns.ATT_QUESTITEMS and ns.ATT_QUESTITEMS[itemID]
  return type(list) == "table" and list or nil
end

local function IsBreadcrumb(questID)
  local q = Q[questID]
  return q and q[FLAGS] and q[FLAGS]:find("b", 1, true) ~= nil or false
end

-- ATT lists some prerequisites that are alternatives, not a chain, without
-- saying how many are needed (prereqsNeeded). One of them is enough when
--   * it is a breadcrumb (the same quest offered in several towns), or
--   * all prerequisites are start quests (no prerequisites of their own) in
--     different zones that lead to exactly the same follow-ups, e.g. the
--     warrior quests from Elwynn, Dun Morogh and Teldrassil before "Vejrek".
-- Static, built once per quest: { [prereqID] = true } or false.
local altCache = {}
local function Alternatives(questID)
  local cached = altCache[questID]
  if cached ~= nil then return cached end
  local pre = Q[questID] and Q[questID][PREREQS]
  local alt = false
  if pre and #pre > 0 then
    for _, id in ipairs(pre) do
      if IsBreadcrumb(id) then alt = alt or {} alt[id] = true end
    end
    if not alt and #pre > 1 then
      local maps, key, siblings = {}, nil, true
      for _, id in ipairs(pre) do
        local p = Q[id]
        local fu = {}
        for _, f in ipairs(FollowUps()[id] or {}) do fu[#fu + 1] = f end
        table.sort(fu)
        local k = table.concat(fu, ",")
        if not (p and p[MAP] and not p[PREREQS]) or maps[p[MAP]] or (key and k ~= key) then
          siblings = false
          break
        end
        maps[p[MAP]], key = true, k
      end
      if siblings then
        alt = {}
        for _, id in ipairs(pre) do alt[id] = true end
      end
    end
  end
  altCache[questID] = alt
  return alt
end
ns.PrereqAlternatives = Alternatives

-- Are the prerequisites done? Prerequisites this character can never do
-- (other faction, race or class) do not count, unless they are done anyway.
local function PrereqsDone(questID, q, player)
  local pre = q[PREREQS]
  if not pre or #pre == 0 then return true end
  if q[NEED] then
    local done = 0
    for _, id in ipairs(pre) do
      if ns.IsQuestDone(id) then done = done + 1 end
    end
    return done >= q[NEED]
  end
  local alt = Alternatives(questID)
  local relevant, anyAlt, altDone = 0, false, false
  for _, id in ipairs(pre) do
    local done = ns.IsQuestDone(id)
    if done or Reachable(id, player) then
      relevant = relevant + 1
      if alt and alt[id] then
        anyAlt = true
        if done then altDone = true end
      elseif not done then
        return false
      end
    end
  end
  if relevant == 0 then return false end
  return not anyAlt or altDone
end

-- A breadcrumb is pointless (and refused by the server) once the quest it
-- leads to is in the log or done.
local function BreadcrumbObsolete(questID)
  if not IsBreadcrumb(questID) then return false end
  for _, nextID in ipairs(FollowUps()[questID] or {}) do
    if ns.IsQuestDone(nextID) or ns.InQuestLog(nextID) then return true end
  end
  return false
end

-- Can this character pick up the quest right now? (ATT data)
-- above (1.22, internal): also true for quests whose minimum level is at most
-- that many levels above the player (everything else must fit); the API and
-- all other callers pass nothing and keep the strict rule.
-- (1.24) Best knowledge: the data's rules, then what the client knows for
-- sure (Offers.lua): false when the quest giver did not offer the quest at
-- this level, or when the client's quest lines say it is not available yet.
-- With above > 0 (dimmed map pins of the next levels) only the data's rules.
local CanTake, DataCanTake
function ns.CanTakeQuest(questID, player, above)
  -- (1.23) the strict rule for this character: once per quest and scope
  if (not player or player == Player()) and not (tonumber(above) and tonumber(above) > 0) then
    return ns.Memo("canTake", questID, CanTake)
  end
  return CanTake(questID, player, above)
end
function DataCanTake(questID, player, above)
  local q = Q[questID]
  if not q then return false end
  player = player or Player()
  if ns.IsQuestDone(questID) or ns.InQuestLog(questID) then return false end
  if ns.QuestKnownMissing(questID) then return false end -- the server does not know it
  if not Reachable(questID, player) then return false end
  if q[SKILL] then return false end -- profession quests: too noisy without a skill check
  if q[LEVEL] and player.level and q[LEVEL] > player.level + (tonumber(above) or 0) then return false end
  if not PrereqsDone(questID, q, player) then return false end
  -- (1.1) helper quests that only exist while another quest is in the log (Data/Extra_Quests.lua)
  local active = ns.EXTRA_ACTIVE and ns.EXTRA_ACTIVE[questID]
  if active and not ns.InQuestLog(active) then return false end
  if BreadcrumbObsolete(questID) then return false end
  return true
end
function CanTake(questID, player, above)
  player = player or Player()
  if not DataCanTake(questID, player, above) then return false end
  -- (1.1) the quest giver never offers it (NotHere.lua): also not as a dimmed pin
  if ns.NeverOffered and ns.NeverOffered(questID) then return false end
  if not (tonumber(above) and tonumber(above) > 0) then
    if ns.NotOfferedLevel and ns.NotOfferedLevel(questID, player.level) then return false end
    if ns.ClientAvailability and ns.ClientAvailability(questID, Q[questID][MAP]) == false then return false end
  end
  ns.CheckQuestExists(questID) -- about to be offered: ask the server (once, rate limited)
  return true
end
-- (1.24) The data's rules only (Offers.lua: is the NPC's answer news?).
function ns.DataCanTakeQuest(questID)
  return DataCanTake(questID, Player())
end

---------------------------------------------------------------------------
-- (1.2) Zone quest list (ZoneQuests.lua): every quest that starts on a map,
-- and why a quest is not available yet.
---------------------------------------------------------------------------
local ORIGIN = 14
-- Quest IDs starting on a map: the data plus what Questdon learned.
function ns.QuestsStartingOnMap(mapID)
  local list, seen = {}, {}
  if not mapID then return list end
  for _, id in ipairs(ByMap()[mapID] or {}) do seen[id] = true list[#list + 1] = id end
  for id, e in pairs(ns.db and ns.db.learned or {}) do
    if not seen[id] and type(e) == "table" and e.start and not e.start.item and e.start.map == mapID then
      seen[id] = true
      list[#list + 1] = id
    end
  end
  return list
end

function ns.QuestInData(questID) return Q[questID] ~= nil end

-- A quest only Questdon learned (not in the data): available to this
-- character by the same rules as on the map (AvailableOnMap). true, or
-- false and why: "faction", "missing", "never", "level", "client".
function ns.LearnedQuestAvailable(questID)
  local e = ns.db and ns.db.learned and ns.db.learned[questID]
  local player = Player()
  local fac = e and (e.faction == "Alliance" and "A" or e.faction == "Horde" and "H") or nil
  if fac and player.faction and fac ~= player.faction then return false, "faction" end
  if ns.QuestKnownMissing(questID) then return false, "missing" end
  if ns.NeverOffered and ns.NeverOffered(questID) then return false, "never" end
  local client = ns.ClientAvailability and ns.ClientAvailability(questID)
  if client == true then return true end
  if player.level and ns.NotOfferedLevel(questID, player.level) then return false, "level" end
  if client == false then return false, "client" end
  return true
end

-- "o": only in ATT's older data, may not exist in Forever (see ATT_Quests.lua).
function ns.QuestOnlyInOldData(questID)
  local q = Q[questID]
  return q ~= nil and q[ORIGIN] == "o"
end

-- (1.3) Previous quests of a quest in the data (for the order of a chain).
function ns.QuestPrereqs(questID)
  local q = Q[questID]
  return q and q[PREREQS] or {}
end

-- First prerequisite this character still has to do (one it can reach), or nil.
function ns.MissingPrereq(questID)
  local q = Q[questID]
  if not q or not q[PREREQS] then return nil end
  local player = Player()
  if PrereqsDone(questID, q, player) then return nil end
  for _, id in ipairs(q[PREREQS]) do
    if not ns.IsQuestDone(id) and Reachable(id, player) then return id end
  end
  return nil
end

-- Breadcrumb whose quest is already in the log or done.
function ns.BreadcrumbObsolete(questID)
  return BreadcrumbObsolete(questID)
end

-- Started by an item (a drop or a found object), not by an NPC you can walk to.
-- (1.0) Quest of a holiday or world event (flag "e"): its quest givers are
-- only there while the event runs, so the data alone cannot say it is available.
function ns.IsEventQuest(questID)
  local q = Q[questID]
  return q and q[FLAGS] and q[FLAGS]:find("e", 1, true) ~= nil or false
end

function ns.IsItemStartQuest(questID)
  local q = Q[questID]
  return q and not q[GIVERS] and q[FLAGS] and q[FLAGS]:find("i", 1, true) ~= nil or false
end

-- (1.22) Level of a quest as far as the data knows it: ATT's minimum level,
-- else the level the client showed when Questdon learned the quest. nil when
-- neither knows it (331 ATT quests have no level): never guessed.
function ns.QuestLevel(questID)
  local q = Q[questID]
  if q and q[LEVEL] then return q[LEVEL] end
  local e = ns.db and ns.db.learned and ns.db.learned[questID]
  local lv = e and ns.Num(e.level)
  if lv and lv > 0 then return lv end
  return nil
end

-- (1.22) "[12] " in difficulty colour, "[?] " for an unknown level.
function ns.QuestLevelTag(questID)
  local lv = ns.QuestLevel(questID)
  if lv then return (ns.LevelColor and ns.LevelColor(lv) or "") .. ("[%d]|r "):format(lv) end
  return "|cff737880[?]|r "
end

-- (1.22) "Level 12" or "Level unknown" for texts.
function ns.QuestLevelText(questID)
  local lv = ns.QuestLevel(questID)
  if lv then return L["Level %d"]:format(lv) end
  return L["Level unknown"]
end

-- (1.22) How many levels below yours a quest counts as low level (option, 3 to 20; was fixed 10).
function ns.LowLevelRange()
  local r = tonumber(ns.db and ns.db.lowLevelRange) or 10
  if r ~= r then r = 10 end
  return math.max(3, math.min(20, math.floor(r + 0.5)))
end

-- Too low for the character (quest level unknown before accepting: use the minimum level).
-- (1.22) range from the option "lowLevelRange"; a level learned from the client
-- counts when ATT has none. (1.24) A quest without any known level is never
-- low level (the option "noLevelIsLow" is gone, see ns.NoLevelHidden).
-- knownOnly: kept for the callers (auto accept), same result now.
function ns.IsLowLevelQuest(questID, player, knownOnly)
  player = player or Player()
  if not player.level then return false end
  local lv = ns.QuestLevel(questID)
  if lv then return lv <= player.level - ns.LowLevelRange() end
  return false
end

-- (1.24) A quest without a minimum level in the data that neither the client
-- (its quest lines) nor a quest giver (offered it to this character, or to
-- the account at or below this level) confirmed. Hidden on the map, the
-- minimap, the nameplates, in the panel and the dungeon list unless the
-- option "showNoLevel" is on. Quests only Questdon learned (not in the data)
-- keep their own rules.
function ns.UnconfirmedNoLevel(questID, player)
  local q = Q[questID]
  if not q or q[LEVEL] then return false end
  player = player or Player()
  if ns.ClientAvailability and ns.ClientAvailability(questID) == true then return false end
  if ns.OfferConfirmed and ns.OfferConfirmed(questID, player.level) then return false end
  return true
end
function ns.NoLevelHidden(questID, player)
  if ns.db and ns.db.showNoLevel then return false end
  return ns.UnconfirmedNoLevel(questID, player)
end

-- (1.24) One rule for "show as available" (map, minimap, nameplates, panel,
-- dungeon list): the client lists it, or the data and the quest givers allow
-- it; low level quests only with "showLowLevel"; unconfirmed quests without
-- a level only with "showNoLevel".
function ns.ShowAsAvailable(questID, player)
  player = player or Player()
  local client = ns.ClientAvailability and ns.ClientAvailability(questID) == true
    and not ns.IsQuestDone(questID) and not ns.InQuestLog(questID)
  if not client and not ns.CanTakeQuest(questID, player) then return false end
  if not ns.db.showLowLevel and ns.IsLowLevelQuest(questID, player) then return false end
  if ns.NoLevelHidden(questID, player) then return false end
  return true
end

-- Ask the server for a quest's data only once per session (Exists.lua): a quest
-- it cannot load answers every request with QUEST_DATA_LOAD_RESULT, which
-- refreshes the map pins, which would ask again (endless refresh while the map
-- is open). The answer also tells whether the quest exists at all.
function ns.QuestTitle(questID)
  local title = ns.Value(C_QuestLog.GetTitleForQuestID, questID)
  if type(title) == "string" and title ~= "" then return title end
  ns.RequestQuestData(questID)
  local learned = ns.db.learned[questID]
  if learned and learned.title then return learned.title end
  local q = Q[questID]
  return q and q[NAME] or ("Quest " .. questID)
end

-- (1.26) The data's (English) name of a quest, nil if unknown.
function ns.DataQuestName(questID)
  local q = Q[questID]
  return q and q[NAME] or nil
end

function ns.QuestMinLevel(questID)
  local q = Q[questID]
  return q and q[LEVEL]
end

function ns.QuestFlags(questID)
  local q = Q[questID]
  return q and q[FLAGS] or ""
end

function ns.QuestGiverIDs(questID)
  local q = Q[questID]
  return q and q[GIVERS]
end

-- Start position (0-100 coordinates) on a map: learned first, then ATT.
function ns.QuestStart(questID)
  local e = ns.db.learned[questID]
  if e and e.start and not e.start.item then return e.start.map, e.start.x * 100, e.start.y * 100, e.start.npc end
  local q = Q[questID]
  if q and q[MAP] and q[X] then return q[MAP], q[X], q[Y], nil end
end

-- Best guess where to turn a quest in: mapID, x, y (0-1), source
-- ("blizzard", "learned", "shared" = reported by other players (1.0.1), "data" = known turn-in NPC,
-- "followup" = giver of the next quest, "giver" = same NPC).
-- giver: also guess the quest giver itself (wrong for delivery quests). Never
-- for quests started by an item (1.15): their "start" is where the item drops.
function ns.TurnInPoint(questID, giver)
  if ns.BlizzardQuestPoint and ns.IsQuestComplete(questID) then
    local m, x, y = ns.BlizzardQuestPoint(questID)
    if m then return m, x, y, "blizzard" end
  end
  local e = ns.db.learned[questID]
  if e and e.finish then return e.finish.map, e.finish.x, e.finish.y, "learned" end
  -- (1.0.1) reported by two or more other players (Exchange.lua)
  if ns.SharedTurnIn then
    local sm, sx, sy = ns.SharedTurnIn(questID)
    if sm then return sm, sx, sy, "shared" end
  end
  -- (1.0) known turn-in NPC (Data/Extra_Quests.lua)
  local fin = ns.QUEST_ENDS and ns.QUEST_ENDS[questID]
  if fin and fin[1] and fin[2] then return fin[1], fin[2] / 100, fin[3] / 100, "data" end
  for _, nextID in ipairs(FollowUps()[questID] or {}) do
    local nq = Q[nextID]
    if nq and nq[MAP] and nq[X] then return nq[MAP], nq[X] / 100, nq[Y] / 100, "followup" end
  end
  if giver and not ns.IsItemStartQuest(questID) then
    local m, x, y = ns.QuestStart(questID)
    if m and x then return m, x / 100, y / 100, "giver" end
  end
end

-- Questie (or Forever Quest Pins) already draws this, so we do not.
local function DrawnElsewhere(questID, what)
  if ns.db.questieFirst and ns.AddOnLoaded("Questie") and ns.QuestieKnows(questID) == true then
    return true
  end
  if what == "start" and ns.AddOnLoaded("ForeverQuestPins") then return true end
  return false
end
ns.DrawnElsewhere = DrawnElsewhere

-- (1.22) For /qd diag: the level options and how many ATT quests have no level.
-- (1.24) "without level hidden unless confirmed" or "shown" (option showNoLevel).
local noLevelCount
function ns.LevelOptionsState()
  if not noLevelCount then
    noLevelCount = 0
    for _, q in pairs(Q) do if not q[LEVEL] then noLevelCount = noLevelCount + 1 end end
  end
  return ("low level from %d below, without level %s (%d quests), next levels +%d"):format(ns.LowLevelRange(),
    ns.db.showNoLevel and "shown" or "hidden unless confirmed", noLevelCount, ns.UpcomingLevels())
end

-- (1.22) Option "upcomingLevels": quests up to that many levels above you (0 = off).
function ns.UpcomingLevels()
  local n = tonumber(ns.db and ns.db.upcomingLevels) or 0
  if n ~= n then n = 0 end
  return math.max(0, math.min(5, math.floor(n + 0.5)))
end

-- Quests available on a map: { {questID, x, y (0-1), npc}, ... }
-- upcoming (1.22, map pins only): also quests you can take within the next
-- ns.UpcomingLevels() levels, marked upcoming = minimum level and dimmed.
-- The panel, the next quest and the API never see them.
-- (1.24) Sources of truth, best first (Offers.lua): the client's quest lines
-- of the map (listed = available, confirmed = true; "not yet" = hidden), the
-- quest givers (not offered at this level = hidden; with upcoming a dimmed pin
-- with notOffered = level), then the data. Unconfirmed quests without a level
-- only with the option "showNoLevel".
local AvailableOnMap
function ns.AvailableQuestsOnMap(mapID, upcoming)
  -- (1.23) once per map and scope (panel, map, minimap share it); callers only read it
  return ns.Memo(upcoming and "availableUp" or "available", mapID, AvailableOnMap, upcoming)
end
function AvailableOnMap(mapID, upcoming)
  local list, seen = {}, {}
  if not mapID then return list end
  local player = Player()
  local above = upcoming and player.level and ns.UpcomingLevels() or 0
  local client = ns.ClientQuestLines and ns.ClientQuestLines(mapID) -- asks the client once per map
  local function Listed(id) return client and client.available[id] and not ns.IsQuestDone(id) and not ns.InQuestLog(id) end
  local function Add(id)
    if seen[id] then return end
    seen[id] = true
    local listed = Listed(id)
    local entry
    if listed or ns.CanTakeQuest(id, player) then
      if not ns.db.showLowLevel and ns.IsLowLevelQuest(id, player) then return end
      if not listed and ns.NoLevelHidden(id, player) then return end
      entry = { confirmed = (listed or ns.OfferConfirmed(id, player.level)) and true or nil }
      -- (1.0) event quests only once confirmed; "confirmedOnly" for every quest
      if not entry.confirmed and (ns.db.confirmedOnly or (ns.db.hideEventQuests and ns.IsEventQuest(id))) then return end
    elseif above > 0 and not ns.db.confirmedOnly and not (ns.db.hideEventQuests and ns.IsEventQuest(id))
        and ns.CanTakeQuest(id, player, above) then
      if not ns.db.showLowLevel and ns.IsLowLevelQuest(id, player) then return end
      local lv = Q[id][LEVEL]
      local refused = ns.NotOfferedLevel(id, player.level)
      if lv and player.level and lv > player.level then
        entry = { upcoming = lv, dimmed = true, notOffered = refused }
      elseif refused then
        entry = { notOffered = refused, dimmed = true }
      else
        return -- the client says "not yet" although the level fits: hidden
      end
    else
      return
    end
    local m, x, y, npc = ns.QuestStart(id)
    if m == mapID and x then
      entry.questID, entry.x, entry.y, entry.npc = id, x / 100, y / 100, npc
      -- (1.25) the game lists it with a spot: it draws its own "!" there
      -- (1.26) only where it really draws one (not hidden, local story, other map)
      if listed and client.drawn and client.drawn[id] then entry.gameShown = true end
      list[#list + 1] = entry
    end
  end
  for _, id in ipairs(ByMap()[mapID] or {}) do Add(id) end
  -- learned quests that ATT does not know (other characters found them)
  for id, e in pairs(ns.db.learned) do
    if e.start and not e.start.item and e.start.map == mapID and not seen[id] then
      seen[id] = true
      local ok
      if Q[id] then
        -- known to ATT (maybe with another start map): use its rules
        ok = (Listed(id) or ns.CanTakeQuest(id, player)) and (ns.db.showLowLevel or not ns.IsLowLevelQuest(id, player))
          and (Listed(id) or not ns.NoLevelHidden(id, player))
          and (Listed(id) or ns.OfferConfirmed(id, player.level) or not (ns.db.confirmedOnly or (ns.db.hideEventQuests and ns.IsEventQuest(id))))
      else
        local fac = e.faction == "Alliance" and "A" or e.faction == "Horde" and "H"
        ok = fac == player.faction and not ns.IsQuestDone(id) and not ns.InQuestLog(id)
          and not ns.QuestKnownMissing(id) and not ns.NotOfferedLevel(id, player.level)
          and not (ns.NeverOffered and ns.NeverOffered(id)) -- (1.1)
          and (Listed(id) or ns.ClientAvailability(id, mapID) ~= false)
          and (Listed(id) or ns.OfferConfirmed(id, player.level) or not ns.db.confirmedOnly)
        if ok then ns.CheckQuestExists(id) end
      end
      if ok then
        list[#list + 1] = { questID = id, x = e.start.x, y = e.start.y, npc = e.start.npc, learned = not Q[id] or nil,
          confirmed = (Listed(id) or ns.OfferConfirmed(id, player.level)) and true or nil,
          gameShown = (Listed(id) and client.drawn and client.drawn[id]) and true or nil } -- (1.25, 1.26)
      end
    end
  end
  -- (1.24) quests the client lists that neither the data nor Questdon know
  if client then
    for id, pos in pairs(client.pos) do
      if not seen[id] and Listed(id) then
        seen[id] = true
        list[#list + 1] = { questID = id, x = pos[1], y = pos[2], learned = true, confirmed = true,
          gameShown = (client.drawn and client.drawn[id]) and true or nil }
      end
    end
  end
  return list
end

---------------------------------------------------------------------------
-- Objective points
-- ATT objective rows: { {creatureIDs}, {itemIDs}, {map,x,y,...}, use, {map,x,y,...} }
-- use = "u" (1.14): an item from {itemIDs} must be USED at an object or place
-- (Marla's Last Wish: loot Samuel's Remains from Samuel Fipps, bury them at
-- Marla's Grave). Rule: never send the player to the place of use before the
-- item is in the bags. The 5th field, if present, is that place.
---------------------------------------------------------------------------
local USE, USE_PTS = 4, 5
local NEAR = 4 -- map units (0-100): "at the quest giver / turn-in"

-- (1.2) Spawn points of a creature from Wowhead's quest maps (Data/Spawns.lua):
-- flat { map, x, y, ... } in 0-100 coordinates, decoded once; nil if none.
local SPAWNS = ns.SPAWNS or {}
local spawnCache = {}
local function Spawns(creatureID)
  local c = spawnCache[creatureID]
  if c ~= nil then return c or nil end
  c = false
  local s = SPAWNS[creatureID]
  if type(s) == "table" then
    c = {}
    for m, enc in pairs(s) do
      for i = 1, #enc - 3, 4 do
        local x, y = tonumber(enc:sub(i, i + 1), 36), tonumber(enc:sub(i + 2, i + 3), 36)
        if x and y then c[#c + 1] = m c[#c + 1] = x / 10 c[#c + 1] = y / 10 end
      end
    end
    if #c == 0 then c = false end
  end
  spawnCache[creatureID] = c
  return c or nil
end
ns.CreatureSpawns = Spawns

-- Where a creature is: Wowhead's spawns, else the few points of the data.
-- fn(map, x, y) per point (0-100). true if any.
local function EachSpawn(creatureID, fn)
  local w = Spawns(creatureID)
  if w then
    for i = 1, #w, 3 do fn(w[i], w[i + 1], w[i + 2]) end
    return true
  end
  local spawns = NPC[creatureID]
  if spawns then
    for i = 2, #spawns, 3 do fn(spawns[i], spawns[i + 1], spawns[i + 2]) end
    return true
  end
  return false
end
ns.EachCreatureSpawn = EachSpawn

-- Count of an item in the bags; nil if unknown (missing API, secret value).
local function ItemCount(itemID)
  local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
  return ns.Num(ns.Value(fn, itemID))
end

-- Item name for texts; falls back to "the quest item".
function ns.ItemName(itemID)
  local name
  if itemID then
    name = C_Item and ns.Value(C_Item.GetItemNameByID, itemID)
    if type(name) ~= "string" or name == "" then name = ns.Value(GetItemInfo, itemID) end
  end
  if type(name) == "string" and name ~= "" then return name end
  return L["the quest item"]
end

-- Does the player have one of the objective's items? Unknown counts as no.
-- Returns has, itemID (the first item, for "first get <item>").
local function HasItem(o)
  local items = o[2] or {}
  for _, itemID in ipairs(items) do
    if (ItemCount(itemID) or 0) > 0 then return true, itemID end
  end
  return false, items[1]
end

local function NearAny(m, x, y, refs)
  for _, r in ipairs(refs) do
    if r[1] == m and math.abs(r[2] - x) < NEAR and math.abs(r[3] - y) < NEAR
        and (r[2] - x) ^ 2 + (r[3] - y) ^ 2 < NEAR * NEAR then
      return true
    end
  end
  return false
end

-- Quest giver and turn-in point (0-100) of a quest: the place of use of a
-- "u" objective is usually there (the grave next to the quest giver).
local function GiverAndTurnIn(questID)
  local refs = {}
  local m, x, y = ns.QuestStart(questID)
  if m and x and not ns.IsItemStartQuest(questID) then refs[#refs + 1] = { m, x, y } end
  local tm, tx, ty = ns.TurnInPoint(questID, true)
  if tm and tx then refs[#refs + 1] = { tm, tx * 100, ty * 100 } end
  return refs
end

-- Points of one unfinished objective (0-1 coordinates):
-- { {mapID, x, y, creature, needsItem, dimmed}, ... }, hint
-- hint = itemID when it is a "u" objective and the item is not in the bags.
-- Without the item: where the item comes from (creature spawns, data points
-- that are not the place of use), marked needsItem; the place of use only
-- dimmed (map). If nothing but the place of use is known: no target at all.
-- With the item: the place of use (or all points if it is not known).
-- onlyMap (1.23, optional): points of other maps are left out where that does
-- not change the result (objectives without an item to use; the "u" split
-- below looks at all points).
function ns.ObjectiveTargets(questID, index, o, spots, onlyMap)
  o = o or {}
  spots = spots or {}
  local out = {}
  local pts = o[3] or {}
  local function Add(list, m, x, y, creature, scale)
    if m and x and y then list[#list + 1] = { mapID = m, x = x / scale, y = y / scale, creature = creature } end
  end
  if o[USE] ~= "u" or #(o[2] or {}) == 0 then
    if onlyMap then
      local add = Add
      Add = function(list, m, x, y, creature, scale) if m == onlyMap then add(list, m, x, y, creature, scale) end end
    end
    -- 1. spots this account has seen the counter go up (0-1 coordinates)
    for i = 1, #spots, 3 do Add(out, spots[i], spots[i + 1], spots[i + 2], nil, 1) end
    -- 2. ATT objective coordinates (0-100)
    for i = 1, #pts, 3 do Add(out, pts[i], pts[i + 1], pts[i + 2], o[1] and o[1][1], 100) end
    -- 3. (1.2) where the objective's creatures are: Wowhead's spawns (all of
    -- them), else the data's creature points (only when the objective has no
    -- points of its own, as before)
    for _, cr in ipairs(o[1] or {}) do
      if Spawns(cr) or #pts == 0 then
        local from = #out
        EachSpawn(cr, function(m, x, y) Add(out, m, x, y, cr, 100) end)
        for k = from + 1, #out do out[k].spawn = true end -- may be thinned out on the map
      end
    end
    -- (1.2) mobs learned to give credit (not in the data): their spawns, if known
    local known = {}
    for _, cr in ipairs(o[1] or {}) do known[cr] = true end
    for _, cr in ipairs(ns.LearnedObjectiveCreatures and ns.LearnedObjectiveCreatures(questID, index, #(o[1] or {}) > 0) or {}) do
      if not known[cr] and Spawns(cr) then
        local from = #out
        EachSpawn(cr, function(m, x, y) Add(out, m, x, y, cr, 100) end)
        for k = from + 1, #out do out[k].spawn = true end
      end
    end
    return out
  end

  -- "u" objective: split into where the item comes from and where it is used.
  local acquire, use = {}, {}
  local known = o[USE_PTS]
  local usePts = {}
  if known and #known >= 3 then
    for i = 1, #known, 3 do usePts[#usePts + 1] = { known[i], known[i + 1], known[i + 2] } end
    -- data points at the object are the place of use: the object's own points stand for them
    for i = 1, #pts, 3 do
      if not NearAny(pts[i], pts[i + 1], pts[i + 2], usePts) then
        Add(acquire, pts[i], pts[i + 1], pts[i + 2], o[1] and o[1][1], 100)
      end
    end
    for _, p in ipairs(usePts) do Add(use, p[1], p[2], p[3], nil, 100) end
  else
    -- heuristic: data points at the quest giver or the turn-in are the place
    -- of use, if at least one other point remains
    local refs = GiverAndTurnIn(questID)
    local near, far = {}, {}
    for i = 1, #pts, 3 do
      local list = NearAny(pts[i], pts[i + 1], pts[i + 2], refs) and near or far
      list[#list + 1] = i
    end
    if #near > 0 and #far > 0 then
      for _, i in ipairs(near) do Add(use, pts[i], pts[i + 1], pts[i + 2], nil, 100) end
      for _, i in ipairs(far) do Add(acquire, pts[i], pts[i + 1], pts[i + 2], o[1] and o[1][1], 100) end
    else
      for i = 1, #pts, 3 do Add(acquire, pts[i], pts[i + 1], pts[i + 2], o[1] and o[1][1], 100) end
    end
  end
  -- the counter goes up where the item is used: learned spots are the place of use
  for i = 1, #spots, 3 do Add(use, spots[i], spots[i + 1], spots[i + 2], nil, 1) end
  -- the creatures drop the item (or are where it is used, then the item is
  -- usually handed out with the quest and already in the bags)
  for _, cr in ipairs(o[1] or {}) do
    local from = #acquire
    EachSpawn(cr, function(m, x, y) Add(acquire, m, x, y, cr, 100) end) -- (1.2) Wowhead's spawns first
    for k = from + 1, #acquire do acquire[k].spawn = true end
  end

  local has, itemID = HasItem(o)
  if has then
    -- (1.26) the place of use is one exact spot (no objective area)
    if #use > 0 then
      for _, p in ipairs(use) do p.useSpot = true end
      return use
    end
    return acquire
  end
  for _, p in ipairs(acquire) do p.needsItem = itemID out[#out + 1] = p end
  for _, p in ipairs(use) do p.needsItem = itemID p.dimmed = true p.useSpot = true end
  return out, itemID, use
end

-- The client's objectives of a quest in the log ({} if unreadable).
-- (1.23) Read once per scope; callers only read the list.
local function ReadObjectives(questID)
  local c = ns.Value(C_QuestLog.GetQuestObjectives, questID)
  return type(c) == "table" and c or {}
end
local function ClientObjectives(questID)
  return ns.Memo("objectives", questID, ReadObjectives)
end
ns.ClientObjectives = ClientObjectives

-- Is objective <index> still open? Unknown state counts as open. An index the
-- loaded client list does not have (ATT knows more objectives than the server
-- quest) is not part of the quest: never a target (1.15).
local function IsOpen(client, index)
  if #client > 0 and index > #client then return false end
  local state = client[index]
  if type(state) ~= "table" then return true end
  return not ns.True(state.finished)
end

-- Sorted indices of the open objectives with data (ATT or learned).
local function OpenIndices(questID, client)
  local objs = OBJ[questID] or {}
  local learned = (ns.ObjectiveSpots and ns.ObjectiveSpots(questID) or (ns.db.learnedObj or {})[questID]) or {} -- (1.0.1) own + shared
  local indices = {}
  for index in pairs(objs) do indices[#indices + 1] = index end
  for index in pairs(learned) do if not objs[index] then indices[#indices + 1] = index end end
  table.sort(indices)
  local open = {}
  for _, index in ipairs(indices) do
    if type(index) == "number" and IsOpen(client, index) then open[#open + 1] = index end
  end
  return open, objs, learned
end

-- Points for the unfinished objectives of quests in the log on one map.
-- { {questID, index, x, y (0-1), text, creature, needsItem, dimmed}, ... }
-- dimmed: place of use of an item the player does not have yet (map only).
-- (1.2) points per objective and per map (all quests): enough to see where
-- the mobs are, few enough for the map, the minimap and the refresh signature
local MAX_OBJ_POINTS, MANY_POINTS, MAX_MAP_POINTS = 80, 25, 400
function ns.ObjectivePointsOnMap(mapID)
  local list = {}
  local total = 0
  if not mapID then return list end
  local learnedObj = ns.db.learnedObj or {}
  for _, info in ipairs(ns.QuestLogEntries()) do
    local id = info.questID
    local tracked = not ns.db.objectivePinsTrackedOnly or ns.IsQuestTracked(id)
    if tracked and (OBJ[id] or learnedObj[id] or (ns.SharedSpots and ns.SharedSpots(id))) and not ns.IsQuestComplete(id) and not ns.IsQuestFailed(id)
        and not DrawnElsewhere(id, "objective") then
      local client = ClientObjectives(id)
      local open, objs, learned = OpenIndices(id, client)
      for _, index in ipairs(open) do
        local state = client[index]
        local text = type(state) == "table" and type(state.text) == "string" and ns.Usable(state.text) and state.text or nil
        local targets, _, usePts = ns.ObjectiveTargets(id, index, objs[index], learned[index], mapID)
        -- (1.2) all spawns (Wowhead), thinned out evenly above MAX_OBJ_POINTS;
        -- many points: smaller dots (map and minimap)
        -- learned spots, data points and the place of use always; the spawns
        -- (many) thinned out evenly to what is left of MAX_OBJ_POINTS
        local keep, spawns = {}, {}
        for _, p in ipairs(targets) do
          if p.mapID == mapID then if p.spawn then spawns[#spawns + 1] = p else keep[#keep + 1] = p end end
        end
        for _, p in ipairs(usePts or {}) do if p.mapID == mapID then keep[#keep + 1] = p end end
        local many = (#keep + #spawns > MANY_POINTS) or nil
        local function Put(p)
          if total >= MAX_MAP_POINTS then return end
          total = total + 1
          list[#list + 1] = { questID = id, index = index, x = p.x, y = p.y, text = text, creature = p.creature,
            needsItem = p.needsItem, dimmed = p.dimmed, small = many }
        end
        for _, p in ipairs(keep) do Put(p) end
        local room = math.max(0, MAX_OBJ_POINTS - #keep)
        if room > 0 and #spawns > 0 then
          local step = #spawns > room and #spawns / room or 1
          local k = 1
          while k <= #spawns + 0.0001 do
            Put(spawns[math.floor(k)])
            k = k + step
          end
        end
      end
    end
  end
  return list
end

-- Visit the unfinished objectives of one quest: fn(index, targets, hint, usePts)
local function EachOpenObjective(questID, fn)
  local open, objs, learned = OpenIndices(questID, ClientObjectives(questID))
  for _, index in ipairs(open) do
    fn(index, ns.ObjectiveTargets(questID, index, objs[index], learned[index]))
  end
end

-- State of a quest's objectives as the client sees them (1.15):
-- total, open (count), openIndex (the only open one, else nil), openTypes
-- ({ [type] = true } of the open ones, e.g. "event" for escorts).
function ns.ObjectiveState(questID)
  local client = ClientObjectives(questID)
  local open, openIndex, types = 0, nil, {}
  for i = 1, #client do
    if IsOpen(client, i) then
      open = open + 1
      openIndex = open == 1 and i or nil
      local t = type(client[i]) == "table" and client[i].type
      if type(t) == "string" and ns.Usable(t) then types[t] = true end
    end
  end
  return #client, open, openIndex, types
end

-- Does an objective of the quest have data (ATT or learned)?
function ns.HasObjectiveData(questID)
  return OBJ[questID] ~= nil or (ns.db.learnedObj or {})[questID] ~= nil or (ns.SharedSpots and ns.SharedSpots(questID)) ~= nil
end

-- Is this ATT objective a "use an item at a place" objective?
function ns.IsUseObjective(questID, index)
  local o = OBJ[questID] and OBJ[questID][index]
  return o and o[USE] == "u" and #(o[2] or {}) > 0 or false
end

-- Places where an item the player does not have yet must be used (1.15):
-- { {mapID, x, y (0-100)}, ... } of all open "u" objectives without their item:
-- known places of use plus quest giver and turn-in (heuristic, see above).
-- Second value: true if a place to get one of these items is known.
function ns.UsePlacesWithoutItem(questID)
  local refs, acquire = {}, false
  local giverRefs
  EachOpenObjective(questID, function(_, targets, hint, usePts)
    if not hint then return end
    if #targets > 0 then acquire = true end
    for _, p in ipairs(usePts or {}) do refs[#refs + 1] = { p.mapID, p.x * 100, p.y * 100 } end
    if not giverRefs then
      giverRefs = GiverAndTurnIn(questID)
      for _, r in ipairs(giverRefs) do refs[#refs + 1] = r end
    end
  end)
  return refs, acquire
end

-- Is (mapID, x, y in 0-1) at one of these places? Same map: NEAR map units;
-- other maps (a continent point): about 100 yards in world coordinates.
local NEAR_YARDS = 100
function ns.AtPlace(mapID, x, y, refs)
  if NearAny(mapID, x * 100, y * 100, refs) then return true end
  if not ns.WorldPos then return false end
  local c, n, w = ns.WorldPos(mapID, x, y)
  if not c then return false end
  for _, r in ipairs(refs) do
    if r[1] ~= mapID then
      local rc, rn, rw = ns.WorldPos(r[1], r[2] / 100, r[3] / 100)
      if rc == c and (rn - n) ^ 2 + (rw - w) ^ 2 < NEAR_YARDS * NEAR_YARDS then return true end
    end
  end
  return false
end

-- Item of an open "u" objective of the super-tracked quest that is in the
-- bags (for the quest item button), else nil.
function ns.TrackedUseItem()
  local questID = C_SuperTrack and ns.Num(ns.Value(C_SuperTrack.GetSuperTrackedQuestID))
  if not questID or questID <= 0 or not ns.InQuestLog(questID) then return nil end
  local objs = OBJ[questID] or {}
  local open = OpenIndices(questID, ClientObjectives(questID))
  for _, index in ipairs(open) do
    if ns.IsUseObjective(questID, index) then
      for _, itemID in ipairs(objs[index][2]) do
        if (ItemCount(itemID) or 0) > 0 then return itemID end
      end
    end
  end
  return nil
end

-- All points (any map, 0-1 coordinates) for the unfinished objectives of one quest.
-- Points may carry needsItem = itemID (1.14): first get that item there.
-- index (1.16): the objective index (client order) the point belongs to.
function ns.AllObjectivePoints(questID)
  local list = {}
  EachOpenObjective(questID, function(index, targets)
    for _, p in ipairs(targets) do
      list[#list + 1] = { mapID = p.mapID, x = p.x, y = p.y, kind = "objective", needsItem = p.needsItem, index = index,
        useSpot = p.useSpot }
    end
  end)
  return list
end

-- itemID when an open objective needs an item the player does not have yet
-- (1.14), else nil. Second value: true if there is a known place to get it.
function ns.ObjectiveHint(questID)
  local item, where
  EachOpenObjective(questID, function(_, targets, hint)
    if hint and not item then item, where = hint, #targets > 0 end
  end)
  return item, where
end

-- (1.27) Creature IDs of the open kill/collect objectives of one quest (drops
-- and kills, not "use an item at a place"). For the target button.
function ns.OpenObjectiveCreatures(questID)
  local list, seen = {}, {}
  if not questID then return list end
  local open, objs = OpenIndices(questID, ClientObjectives(questID))
  for _, index in ipairs(open) do
    local o = objs[index]
    if o and o[USE] ~= "u" then
      for _, cr in ipairs(o[1] or {}) do
        if not seen[cr] then seen[cr] = true list[#list + 1] = cr end
      end
    end
  end
  return list
end

-- Tracked in the quest tracker or super-tracked.
function ns.IsQuestTracked(questID)
  if C_SuperTrack and ns.Value(C_SuperTrack.GetSuperTrackedQuestID) == questID then return true end
  if C_QuestLog.GetQuestWatchType then return ns.Value(C_QuestLog.GetQuestWatchType, questID) ~= nil end
  if C_QuestLog.IsQuestWatched then return ns.True(ns.Value(C_QuestLog.IsQuestWatched, questID)) end
  return true
end

-- Nearest quest you can take in your current zone: { questID, x, y, mapID, dist }
-- Optional: a list from ns.AvailableQuestsOnMap(mapID) that is already at hand.
-- (1.24) Quests with a known level (or confirmed by the client or a quest
-- giver) come first: a quest of unknown level that nobody confirmed is only
-- the next quest when there is no other (option "showNoLevel").
local function Trusted(a)
  return a.confirmed or ns.QuestLevel(a.questID) ~= nil
end
-- (1.0) Only "nearby": farther than this a quest is no help as the next step
-- (the map and minimap show the game's own ! anyway).
ns.NEXT_MAX_YARDS = 400
function ns.NearestAvailableQuest(available, mapID)
  mapID = mapID or ns.Num(ns.Value(C_Map.GetBestMapForUnit, "player"))
  if not mapID then return nil end
  local best, bestTrusted = nil, false
  -- (1.23) the player's position once, not once per quest
  local pc, pn, pw
  if ns.PlayerWorld then pc, pn, pw = ns.PlayerWorld() end
  if not pc then return nil end
  local target = { mapID = mapID }
  for _, a in ipairs(available or ns.AvailableQuestsOnMap(mapID)) do
    -- item start quests cannot be picked up at a spot: no "next quest" there
    local dist
    if not ns.IsItemStartQuest(a.questID) and not a.dimmed and (a.confirmed or not ns.db.nextConfirmedOnly) then
      target.x, target.y = a.x, a.y
      dist = ns.DistanceFrom(pc, pn, pw, target)
    end
    if dist and dist > ns.NEXT_MAX_YARDS then dist = nil end
    if dist then
      local trusted = Trusted(a)
      if not best or (trusted and not bestTrusted) or (trusted == bestTrusted and dist < best.dist) then
        best = { questID = a.questID, x = a.x, y = a.y, mapID = mapID, dist = dist }
        bestTrusted = trusted
      end
    end
  end
  return best
end

function ns.PointToNextQuest()
  local n = ns.NearestAvailableQuest()
  if not n then ns.Print(L["No quest available nearby."]) return end
  if ns.SetArrowTarget then
    ns.db.arrow = true
    if ns.ApplyArrow then ns.ApplyArrow() end
    ns.SetArrowTarget(n.mapID, n.x, n.y, ns.QuestTitle(n.questID))
  end
end

function ns.CreatureName(creatureID)
  local c = NPC[creatureID]
  return c and c[1]
end

---------------------------------------------------------------------------
function ns.FollowUpQuests(questID)
  return FollowUps()[questID] or {}
end

-- Next quest in a chain after turning one in
---------------------------------------------------------------------------
ns.On("QUEST_TURNED_IN", function(_, questID)
  questID = ns.Num(questID) -- (1.23) a secret ID must not become a table key
  if not ns.db.chainHint or not questID then return end
  -- ask about the follow-ups now, so the answer is there before the hint
  for _, nextID in ipairs(FollowUps()[questID] or {}) do
    if not ns.InQuestLog(nextID) then ns.CheckQuestExists(nextID) end
  end
  ns.After(1.5, function()
    local player = Player()
    for _, nextID in ipairs(FollowUps()[questID] or {}) do
      if ns.CanTakeQuest(nextID, player) then
        local m = ns.QuestStart(nextID)
        local info = m and ns.Value(C_Map.GetMapInfo, m)
        local where = type(info) == "table" and info.name
        if type(where) == "string" and ns.Usable(where) then
          ns.Print(L["Next in the chain: %s (%s)"]:format(ns.QuestTitle(nextID), where))
        else
          ns.Print(L["Next in the chain: %s"]:format(ns.QuestTitle(nextID)))
        end
      end
    end
  end)
end)
