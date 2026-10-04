local _, ns = ...

---------------------------------------------------------------------------
-- Read-only interface for other addons (e.g. a guide addon).
-- Versioned: add functions, never change existing ones. Bump VERSION only
-- when something is added; other addons check QuestdonAPI.version.
---------------------------------------------------------------------------
local VERSION = 1
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
function API.GetQuest(questID)
  local q = Q[questID]
  if not q then return nil end
  return {
    questID = questID, mapID = q[1], x = q[2], y = q[3], faction = q[4], minLevel = q[5],
    prereqs = Copy(q[6]), givers = Copy(q[7]), flags = q[8] or "", name = q[13], origin = q[14],
    dungeon = q[15],
  }
end

function API.QuestTitle(questID) return ns.QuestTitle(questID) end
-- CanTakeQuest: can this character pick the quest up right now, by best
-- knowledge. Data rules (level, faction, race, class, prerequisites), false for
-- quests the server does not know (1.13), and (1.24) false when this
-- character's quest giver did not offer it at the current level (until the
-- level rises) or when the client's quest lines say it is not available yet.
function API.CanTakeQuest(questID) return ns.CanTakeQuest(questID) end
function API.IsQuestDone(questID) return ns.IsQuestDone(questID) end
function API.InQuestLog(questID) return ns.InQuestLog(questID) end
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
function API.ObjectivePoints(questID)
  local list = {}
  local m, x, y, kind, source = ns.QuestPOI(questID)
  if m and kind == "objective" then
    local openIndex = ns.ObjectiveState and select(3, ns.ObjectiveState(questID)) or nil
    list[1] = { mapID = m, x = x, y = y, source = source, index = openIndex }
  end
  for _, p in ipairs(ns.AllObjectivePoints(questID)) do
    list[#list + 1] = { mapID = p.mapID, x = p.x, y = p.y, needsItem = p.needsItem, index = p.index }
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

-- (1.18) Quest progress of group members who use Questdon (party of up to five):
-- { { name, complete, failed, objectives = { {fulfilled, required}, ... } }, ... },
-- empty when nobody in the group has the quest or the option is off.
function API.PartyProgress(questID)
  return ns.PartyProgress and ns.PartyProgress(questID) or {}
end

-- Distance in yards from the player (nil if another continent / no position)
function API.DistanceTo(mapID, x, y)
  return ns.DistanceAndBearing and ns.DistanceAndBearing({ mapID = mapID, x = x, y = y }) or nil
end

-- Arrow: point it at a target { mapID, x, y (0-1), label } or nil to release it.
function API.SetArrowTarget(target)
  if ns.SetExternalArrowTarget then ns.SetExternalArrowTarget(target) end
end

QuestdonAPI = API
QuestKompassAPI = API -- old name, kept for addons written against it
