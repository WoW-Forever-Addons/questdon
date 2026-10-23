local _, ns = ...

---------------------------------------------------------------------------
-- Read-only interface for other addons (e.g. a guide addon).
-- Versioned: add functions, never change existing ones. Bump VERSION only
-- when something is added; other addons check QuestdonAPI.version.
--   1: the first set
--   2: (1.3.5) CanTakeQuestLater (Leveldon, 09.10.), DungeonLevelRange, Dungeons, DungeonsForLevel
--      (Geardon, 10.10.)
---------------------------------------------------------------------------
local VERSION = 2
local Q = ns.ATT_QUESTS or {}

local function Copy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

local API = { version = VERSION }

-- Static data: { questID, mapID, x, y (0-100), faction "A"/"H"/nil, minLevel, prereqs, givers, flags, name,
-- origin } origin (1.13): nil = ATT's current Forever data, "o" = only in ATT's older classic data
-- (zzOLD, may be gone in Forever), "of" = zzOLD but marked by ATT as added in Forever.
-- dungeon (1.18): ATT instance ID of the dungeon the quest belongs to, else nil (see QuestDungeon).
-- (23.10., Daniel's /qd mem with Leveldon: "API GetQuest" 3 KB a second at 2.5 calls) the data does not change: one
-- answer table per quest, kept (callers only read it)
local questAnswers = {}
function API.GetQuest(questID)
  local q = Q[questID]
  if not q then return nil end
  local kept = questAnswers[questID]
  if kept and kept.q == q then return kept.out end
  local out = {
    questID = questID, mapID = q[1], x = q[2], y = q[3], faction = q[4], minLevel = q[5],
    prereqs = Copy(q[6]), givers = Copy(q[7]), flags = q[8] or "", name = q[13], origin = q[14],
    dungeon = q[15],
    classes = Copy(q[9]), -- (1.3.6) class IDs of a class quest (1 warrior ... 11 druid), else nil
  }
  questAnswers[questID] = { q = q, out = out }
  return out
end

function API.QuestTitle(questID) return ns.QuestTitle(questID) end
-- CanTakeQuest: can this character pick the quest up right now, by best
-- knowledge. Data rules (level, faction, race, class, prerequisites), false for
-- quests the server does not know (1.13), and (1.24) false when this
-- character's quest giver did not offer it at the current level (until the
-- level rises) or when the client's quest lines say it is not available yet.
function API.CanTakeQuest(questID) return ns.CanTakeQuest(questID) end
-- (API 2, Leveldon 09.10.) CanTakeQuestLater: could this character take the quest once its level is high
-- enough? false when something else blocks it: a prerequisite not done, faction, race, class, profession,
-- a quest the server does not know. A guide skips such a quest instead of waiting for it.
function API.CanTakeQuestLater(questID)
  if ns.IsQuestDone(questID) or ns.InQuestLog(questID) then return false end
  return ns.CanTakeQuest(questID, nil, 100) and true or false
end
-- (1.3.6, Leveldon) the level at which this character's quest giver did not offer the quest (Questdon read
-- the NPC's dialog), while that holds (until a level up), else nil
function API.NotOfferedLevel(questID) return ns.NotOfferedLevel and ns.NotOfferedLevel(questID) or nil end
function API.IsQuestDone(questID) return ns.IsQuestDone(questID) end
function API.InQuestLog(questID) return ns.InQuestLog(questID) end
-- (1.3.6) the quest giver (turnin false) or turn-in NPC walks around (seen at places far apart, or known)
function API.QuestNpcWalks(questID, turnin) return ns.QuestNpcWalks and ns.QuestNpcWalks(questID, turnin) or false end
function API.IsQuestComplete(questID) return ns.IsQuestComplete(questID) end
function API.CreatureName(creatureID) return ns.CreatureName(creatureID) end

-- Does the quest exist on this server? (1.13)
-- true: in the log or confirmed by the server this session; false: the server
-- said it does not know the quest (CanTakeQuest is then false too); nil:
-- unknown, the server is asked (answer within seconds, QUEST_DATA_LOAD_RESULT).
function API.QuestExists(questID) return ns.QuestExists(questID) end

-- Where to pick the quest up: mapID, x, y (0-1), npcName
function API.QuestStart(questID)
  local m, x, y, npc = ns.QuestStart(questID)
  if not m or not x then return nil end
  return m, x / 100, y / 100, npc
end

-- Points (0-1) for unfinished objectives of a quest in the log: { {mapID, x, y}, ... }
-- 1.14: a point may carry needsItem = itemID: the objective needs that item used
-- somewhere else, and this is where to get it. The place of use is not among the
-- points until the item is in the bags.
-- 1.15: Blizzard's own objective point (see QuestPOI) comes first, with
-- source = "blizzard"; the other points have no source field.
-- 1.16: optional index = objective index (client order, as in
-- C_QuestLog.GetQuestObjectives) the point belongs to. The Blizzard point
-- carries it only when exactly one objective is still open.
-- (16.10. late, Daniel's /qd mem) Leveldon asks for a quest's places several times a second (its window, the
-- nearest spot, the route fitting): the list is kept while the quest's state is the same (the arrow's signature:
-- complete, objectives done, the game's point, learned and shared places), until the bags change (an item to use,
-- an item to get), the zone changes or 30 seconds passed. The same table is returned: callers only read it.
local apiPts = {} -- [questID] = { sig =, at =, list =, bags = } (bags: its places depend on the bags)
for _, e in ipairs({ "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
  ns.On(e, function() apiPts = {} end)
end
-- (16.10. late) looting gives a bag update every few seconds: only the quests whose places depend on the bags
ns.On("BAG_UPDATE_DELAYED", function()
  for q, c in pairs(apiPts) do if c.bags then apiPts[q] = nil end end
end)
local lastBags
local apiSeen = {} -- (23.10., /qd mem) quests whose places were asked for before (to tell a forgotten entry from a first one)
function ns.ForgetApiPoints() apiPts = {} end -- (tests)
local BuildObjectivePoints
function API.ObjectivePoints(questID)
  questID = ns.Num(questID)
  if not questID or not ns.QuestStampSame then return BuildObjectivePoints(questID) end
  local now = ns.Num(ns.Value(GetTime)) or 0
  local c = apiPts[questID]
  if c and now - c.at <= 30 and now >= c.at and ns.QuestStampSame(questID, c.st) then return c.list end
  -- (23.10.) while /qd mem runs: why the places were worked out again ("first" also after a bag or zone change)
  if c and ns.QuestStampWhy then ns.QuestStampWhy(questID, c.st, "API points new")
  elseif ns.MemProfiling and ns.MemProfiling() then ns.MemCount(apiSeen[questID] and "API points new: bags or zone" or "API points new: first") end
  apiSeen[questID] = true
  local list = BuildObjectivePoints(questID)
  apiPts[questID] = { st = ns.QuestStampFill(questID, {}), at = now, list = list, bags = lastBags or #list == 0 }
  return list
end
function BuildObjectivePoints(questID)
  local list = {}
  local m, x, y, kind, source = ns.QuestPOI(questID)
  if m and kind == "objective" then
    local openIndex = ns.ObjectiveState and select(3, ns.ObjectiveState(questID)) or nil
    list[1] = { mapID = m, x = x, y = y, source = source, index = openIndex }
  end
  lastBags = false
  -- (23.10.) the points of AllObjectivePoints are new tables of this call: handed on as they are (they were copied
  -- into a second set of tables)
  for _, p in ipairs(ns.AllObjectivePoints(questID)) do
    if p.needsItem or p.useSpot then lastBags = true end
    list[#list + 1] = p
  end
  return list
end

-- (1.15) Blizzard's own point for a quest in the log (the client's quest POI
-- or next waypoint): mapID, x, y (0-1), kind ("objective" or "turnin"),
-- source ("blizzard"). nil when the client has none, the quest failed, or the
-- point is where an item must be used that the player does not have yet.
function API.QuestPOI(questID)
  local m, x, y, kind, source = ns.QuestPOI(questID)
  if not m then return nil end
  return m, x, y, kind, source
end

-- (1.14) itemID when an open objective needs an item the player does not have
-- yet (to use at a place), else nil. Second value: true if ObjectivePoints has
-- a place to get it; false: nothing known, say "first get <item>" instead.
function API.ObjectiveHint(questID)
  return ns.ObjectiveHint(questID)
end

-- (1.14) Item name for texts (falls back to "the quest item", localized).
function API.ItemName(itemID) return ns.ItemName(itemID) end

-- Best guess where to turn the quest in: mapID, x, y (0-1), source
-- ("blizzard", "learned", "data" = known turn-in NPC, "followup" = giver of the next quest, "giver" = same NPC;
-- 1.15: never "giver" for quests started by an item)
function API.TurnInPoint(questID)
  return ns.TurnInPoint(questID, true)
end

-- (1.18) Dungeon of a quest: instanceID (ATT), localized name, uiMapID of the
-- dungeon, minimum level of the dungeon; nil when the quest is no dungeon quest.
function API.QuestDungeon(questID)
  local inst = ns.QuestDungeon(questID)
  if not inst then return nil end
  local d = ns.ATT_DUNGEONS and ns.ATT_DUNGEONS[inst] or {}
  return inst, ns.DungeonName(inst), d[2], d[6]
end

-- (API 2, 1.3.5, Geardon 10.10.) Level range of a dungeon (ATT instance ID): min, max, source ("game" = the
-- client's Group Finder, "data" = Questdon's table); nil when unknown.
function API.DungeonLevelRange(inst)
  local lo, hi, source = ns.DungeonLevelRange(inst)
  if not lo then return nil end
  return lo, hi or lo, source
end

-- (API 2) Every dungeon and raid of the data with a level range:
-- { { inst, name (localized), min, max, source, raid (true for 60-60 raids), entranceMap, entranceX, entranceY (0-1, nil if
-- unknown) }, ... } sorted by min, max, inst.
function API.Dungeons()
  local list = {}
  for inst in pairs(ns.ATT_DUNGEONS or {}) do
    local lo, hi, source = ns.DungeonLevelRange(inst)
    if lo then
      local m, x, y = ns.DungeonEntrance(inst)
      list[#list + 1] = { inst = inst, name = ns.DungeonName(inst), min = lo, max = hi or lo, source = source,
        raid = (lo >= 60 and (hi or lo) >= 60) or nil, entranceMap = m, entranceX = x, entranceY = y }
    end
  end
  table.sort(list, function(a, b)
    if a.min ~= b.min then return a.min < b.min end
    if a.max ~= b.max then return a.max < b.max end
    return a.inst < b.inst
  end)
  return list
end

-- (API 2) The dungeons whose range holds level (default: the player's), same entries as Dungeons().
function API.DungeonsForLevel(level)
  level = tonumber(level) or ns.PlayerLevel()
  local out = {}
  if not level then return out end
  for _, d in ipairs(API.Dungeons()) do
    if level >= d.min and level <= d.max then out[#out + 1] = d end
  end
  return out
end

-- (1.18) Quest progress of group members who use Questdon (party of up to five):
-- { { name, complete, failed, objectives = { {fulfilled, required}, ... } }, ... },
-- empty when nobody in the group has the quest or the option is off.
function API.PartyProgress(questID)
  return ns.PartyProgress and ns.PartyProgress(questID) or {}
end

-- Distance in yards from the player (nil if another continent / no position)
-- (16.10.) one target table for all calls (the arrow's world position cache compares its fields, not only the table)
local distTarget = {}
function API.DistanceTo(mapID, x, y)
  if not ns.DistanceAndBearing then return nil end
  distTarget.mapID, distTarget.x, distTarget.y = mapID, x, y
  return ns.DistanceAndBearing(distTarget)
end

-- (23.10., Leveldon's /lvd mem) the player's map and position (0-1) as Questdon reads it: from UnitPosition where it
-- fits the map, so no new vector table as with C_Map.GetPlayerMapPosition. nil without a position.
function API.PlayerPosition()
  if not ns.PlayerPosition then return nil end
  return ns.PlayerPosition()
end

-- Arrow: point it at a target { mapID, x, y (0-1), label } or nil to release it.
-- (1.3.6) { ..., area = true, questID, points = { { mapID, x, y }, ... } }: the quest's objective places; in
-- their area (or with its mobs in sight) the needle gives way to "In the objective area", as for Questdon's own.
function API.SetArrowTarget(target)
  if ns.SetExternalArrowTarget then ns.SetExternalArrowTarget(target) end
end

-- (1.3.6, Daniel 12.10.: "the arrow built into the window") For a guide window with its own compass:
--   API.NewCompass(parent, size)        Questdon's compass (ring, rose, golden needle): c:Point(bearing, facing,
--                                       nearness), c:Arrived(on)
--   API.ArrowState()                    what the arrow shows now: angle (its needle's rotation), needle, nearness,
--                                       seal (arrived), label, distText, distColor, dist, bearing (to the target
--                                       itself, radians clockwise from north; the needle may follow a way around)
--   API.SetGuideCompass(on)             the guide's window shows the compass: Questdon's arrow draws nothing and its
--                                       quest list leaves out its own card (the quests stay listed)
--   API.ShowQuestText(questID)          the whole quest to read (description, objectives, rewards)
function API.NewCompass(parent, size) return ns.NewCompass and ns.NewCompass(parent, size) or nil end
-- (16.10. late, /qd mem "API ArrowState" 12 KB a second: a guide window asks many times a second) one answer table,
-- filled anew at each call: read it right away, do not keep it
local arrowAnswer = {}
function API.ArrowState()
  local st = ns.ArrowState and ns.ArrowState() or {}
  local r = arrowAnswer
  r.angle, r.needle, r.nearness, r.seal, r.label = st.angle, st.needle, st.nearness, st.seal, st.label
  r.distText, r.distColor, r.dist, r.hasTarget, r.bearing = st.distText, st.distColor, st.dist, st.t ~= nil, st.bearing
  -- (Questdon review 5) the distance and the way apart ("240 yards" / "the way around"), as Questdon's card has
  -- them; nil when the text is not "N yards, ..." (in the objective area, arrived, other zone)
  r.distShort, r.distWay = st.distShort, st.distWay
  return r
end
function API.SetGuideCompass(on)
  ns.guideCompass = on and true or nil
  if ns.QueueRefresh then ns.QueueRefresh("tracker") end
end
-- (1.3.6) The mobs of a quest's objectives: { [index] = { ids = { creatureID, ... }, need = n or nil, done } }
-- (data creatures; need and done from the game for a quest in the log)
-- (17.10.) kept until the next quest log event (the same table: callers only read it)
local apiCreatures, apiCreaturesGen = {}, {}
local BuildObjectiveCreatures
function API.ObjectiveCreatures(questID)
  local gen = ns.LogGen and ns.LogGen()
  if gen and type(questID) == "number" then
    if apiCreaturesGen[questID] == gen and apiCreatures[questID] then return apiCreatures[questID] end
    local out = BuildObjectiveCreatures(questID)
    apiCreatures[questID], apiCreaturesGen[questID] = out, gen
    return out
  end
  return BuildObjectiveCreatures(questID)
end
function BuildObjectiveCreatures(questID)
  local out = {}
  local objs = ns.ATT_OBJECTIVES and ns.ATT_OBJECTIVES[questID]
  local client = ns.InQuestLog(questID) and ns.ClientObjectives(questID) or {}
  if type(objs) ~= "table" then return out end
  for idx, o in pairs(objs) do
    if type(idx) == "number" and type(o) == "table" and type(o[1]) == "table" and #o[1] > 0 then
      local c = client[idx]
      out[idx] = { ids = Copy(o[1]), need = type(c) == "table" and ns.Num(c.numRequired) or nil,
        done = type(c) == "table" and ns.True(c.finished) or false }
    end
  end
  return out
end
-- (1.3.6) Who takes a quest: creature ID (nil if unknown) and name (game language where known)
function API.TurnInNpc(questID)
  local e = ns.QUEST_ENDS and ns.QUEST_ENDS[questID]
  local id = e and ns.Num(e[4]) or nil
  local name = id and ns.LocalNpcName and ns.LocalNpcName(id) or nil
  local learned = ns.db and ns.db.learned and ns.db.learned[questID]
  return id, name or (learned and learned.finish and learned.finish.npc) or nil
end
-- (1.3.6) the guide's window: Questdon's quest list docks right under it (same width, moves with it); nil undocks
function API.SetGuideFrame(frame)
  if ns.guideFrame == frame then return end
  ns.guideFrame = frame
  if ns.TrackerDock then ns.TrackerDock() end
  if ns.QueueRefresh then ns.QueueRefresh("tracker") end
end
-- (1.3.6) A guide that draws its own mark over a nameplate claims it: fn(unit) true means Questdon draws
-- nothing on that nameplate. RefreshPlate(unit): the guide's mark came or went.
-- (1.3.6) the number of Questdon's open channel (QuestdonNet) while joined, else nil: Leveldon shares how its
-- routes go there (its own addon prefix)
function API.ShareChannelID() return ns.ShareChannelID and ns.ShareChannelID() or nil end
function API.SetPlateClaim(fn) ns.plateClaim = type(fn) == "function" and fn or nil end
function API.RefreshPlate(unit) if ns.NameplateApply then pcall(ns.NameplateApply, unit) end end
function API.ShowQuestText(questID) if ns.ShowQuestText then return ns.ShowQuestText(questID) ~= nil end return false end

-- (17.10., Daniel: "Leveldon's options menu in Questdon's look") an options window like Questdon's own for another
-- addon: spec = { frameName, wordmark, media (path of its pictures, ending in \\), tabs (as OptionsWindow.lua's:
-- key, title, text, pic, icon, main, more, tools), pages() (as Options.lua's: items with key, name, tip, kind,
-- parent, min/max/step, onClick), tools() ({ name, button, fn, tip }), db() (the saved table), default(key),
-- changed(key), T(text) (the addon's translation) }. Returns { Open(tab), Toggle(), Render(), Frame() } or nil.
function API.NewOptionsWindow(spec)
  if type(spec) ~= "table" or not ns.NewOptionsWindow or type(spec.pages) ~= "function" or type(spec.db) ~= "function" then return nil end
  spec.default = spec.default or function() return nil end
  local w = ns.NewOptionsWindow(spec)
  return { Open = w.Open, Toggle = w.Toggle, Render = w.Render, Frame = w.Frame }
end

-- (17.10.) every API function in a scope of its own (Core.lua ns.ScopeCall)
for k, f in pairs(API) do
  if type(f) == "function" then API[k] = function(...) return ns.ScopeCall(f, ...) end end
end

QuestdonAPI = API
QuestKompassAPI = API -- old name, kept for addons written against it
