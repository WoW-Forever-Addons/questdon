local _, ns = ...

---------------------------------------------------------------------------
-- Blizzard's own quest locations (1.15). The modern client knows where the
-- objectives and the turn-in of quests in the log are (the quest POIs it
-- draws on its world map). Questdon prefers them to the bundled data:
--
--   * C_QuestLog.GetQuestsOnMap(uiMapID): quest POIs on one map, asked for the
--     player's map, the map open in the world map and the parent maps up to
--     the continent. Cached per map, rebuilt at most once per second after
--     QUEST_LOG_UPDATE, QUEST_POI_UPDATE, ZONE_CHANGED_NEW_AREA or a new map.
--   * C_QuestLog.GetNextWaypoint(questID) (or GetNextWaypointForMap): the next
--     step when the target lies in another zone (a boat, a path).
--
-- Order: POI on the player's (or a zone) map, then the waypoint, then a POI on
-- a continent map. Every call is protected; secret values are skipped.
-- Read only: nothing of Blizzard's is changed or hooked.
---------------------------------------------------------------------------
local MIN_INTERVAL = 1   -- seconds between two rebuilds
local DIFF = 8           -- map units (0-100): Blizzard's point "differs strongly" from the data
local ZONE_TYPE = 3      -- Enum.UIMapType.Zone; Continent = 2, World = 1, Cosmic = 0

local maps = {}          -- { {mapID, level = "zone" | "continent"} }, most specific first
local onMap = {}         -- [mapID] = { [questID] = { x, y } }
local dirty, lastBuild, lastPlayerMap, rebuildQueued = true, nil, nil, false
local stats = { maps = 0, learned = 0, skippedUse = 0 }

local function Now() return ns.Num(ns.Value(GetTime)) or 0 end

local function Fn(path)
  local t = C_QuestLog
  return type(t) == "table" and type(t[path]) == "function" and t[path] or nil
end

local function MapType(mapID)
  local info = C_Map and ns.Value(C_Map.GetMapInfo, mapID)
  return type(info) == "table" and ns.Num(info.mapType) or nil, type(info) == "table" and ns.Num(info.parentMapID) or nil
end

-- Maps to ask: the player's map, the open world map, the parents (to the continent).
local function MapsToAsk(playerMap)
  local list, seen = {}, {}
  local function Add(m, level)
    if m and m > 0 and not seen[m] then seen[m] = true list[#list + 1] = { mapID = m, level = level } end
  end
  Add(playerMap, "zone")
  if WorldMapFrame and type(WorldMapFrame.IsShown) == "function" and type(WorldMapFrame.GetMapID) == "function" then
    local ok, shown = pcall(WorldMapFrame.IsShown, WorldMapFrame)
    if ok and ns.True(shown) then
      local ok2, m = pcall(WorldMapFrame.GetMapID, WorldMapFrame)
      m = ok2 and ns.Num(m) or nil
      if m then
        local t = MapType(m)
        Add(m, (t and t >= ZONE_TYPE) and "zone" or "continent")
      end
    end
  end
  local m = playerMap
  for _ = 1, 4 do
    local t, parent = MapType(m)
    if not parent or parent <= 0 or (t and t <= 2) then break end
    local pt = MapType(parent)
    Add(parent, (pt and pt >= ZONE_TYPE) and "zone" or "continent")
    m = parent
  end
  return list
end

-- Quest POIs of one map: { [questID] = { x, y } } (0-1, readable only).
local function ReadMap(mapID)
  local out = {}
  local fn = Fn("GetQuestsOnMap")
  local list = fn and ns.Value(fn, mapID)
  if type(list) ~= "table" then return out end
  for i = 1, #list do
    local ok, id, x, y, indicator = pcall(function()
      local e = list[i]
      if type(e) ~= "table" then return nil end
      return e.questID, e.x, e.y, e.isMapIndicatorQuest
    end)
    id, x, y = ok and ns.Num(id), ok and ns.Num(x), ok and ns.Num(y)
    -- map indicator entries only say "somewhere over there", no place
    if id and x and y and not (ok and ns.True(indicator)) and x >= 0 and x <= 1 and y >= 0 and y <= 1
        and not (x == 0 and y == 0) and not out[id] then
      out[id] = { x = x, y = y }
    end
  end
  return out
end

local Learn

local function Rebuild()
  dirty, lastBuild = false, Now()
  local playerMap = ns.Num(C_Map and ns.Value(C_Map.GetBestMapForUnit, "player"))
  lastPlayerMap = playerMap
  maps, onMap = {}, {}
  if not Fn("GetQuestsOnMap") then stats.maps = 0 return end
  maps = MapsToAsk(playerMap)
  for _, m in ipairs(maps) do onMap[m.mapID] = ReadMap(m.mapID) end
  stats.maps = #maps
  if ns.db and ns.db.learnQuests then ns.SafeCall("poi learn", Learn) end
end

-- Up to date (throttled): a newer request within MIN_INTERVAL is handled by a timer.
local function Ensure()
  local playerMap = ns.Num(C_Map and ns.Value(C_Map.GetBestMapForUnit, "player"))
  if playerMap ~= lastPlayerMap then dirty = true end
  if not dirty then return end
  local wait = lastBuild and (lastBuild + MIN_INTERVAL - Now()) or 0
  if wait <= 0 then Rebuild() return end
  if not rebuildQueued then
    rebuildQueued = true
    ns.After(wait, function()
      rebuildQueued = false
      if dirty then Rebuild() end
      if ns.UpdateArrowTarget then ns.UpdateArrowTarget() end
    end)
  end
end

local function Waypoint(questID)
  local fn = Fn("GetNextWaypoint")
  if fn then
    local ok, m, x, y = pcall(fn, questID)
    m, x, y = ok and ns.Num(m), ok and ns.Num(x), ok and ns.Num(y)
    if m and x and y and not (x == 0 and y == 0) then return m, x, y end
  end
  fn = Fn("GetNextWaypointForMap")
  local playerMap = lastPlayerMap
  if fn and playerMap then
    local ok, x, y = pcall(fn, questID, playerMap)
    x, y = ok and ns.Num(x), ok and ns.Num(y)
    if x and y and not (x == 0 and y == 0) then return playerMap, x, y end
  end
end

-- Blizzard's point for a quest in the log, unfiltered:
-- mapID, x, y (0-1), level ("zone", "waypoint", "continent") or nil.
function ns.BlizzardQuestPoint(questID)
  questID = ns.Num(questID)
  if not questID or not ns.InQuestLog(questID) then return nil end
  Ensure()
  for _, m in ipairs(maps) do
    local p = m.level == "zone" and onMap[m.mapID] and onMap[m.mapID][questID]
    if p then return m.mapID, p.x, p.y, "zone" end
  end
  local wm, wx, wy = Waypoint(questID)
  if wm then return wm, wx, wy, "waypoint" end
  for _, m in ipairs(maps) do
    local p = m.level == "continent" and onMap[m.mapID] and onMap[m.mapID][questID]
    if p then return m.mapID, p.x, p.y, "continent" end
  end
end

-- Is Blizzard's objective point the place where an item must be used that the
-- player does not have yet? Then the item has to be fetched first (1.14 rule).
local function AtUsePlaceWithoutItem(questID, m, x, y)
  if not ns.UsePlacesWithoutItem then return false end
  local refs = ns.UsePlacesWithoutItem(questID)
  return #refs > 0 and ns.AtPlace(m, x, y, refs)
end

-- Blizzard's point as Questdon uses it: mapID, x, y (0-1), kind ("objective" or
-- "turnin"), "blizzard", level. nil when there is none, the quest failed, or
-- the point is the place of use of an item still missing.
function ns.QuestPOI(questID)
  questID = ns.Num(questID)
  if not questID or ns.IsQuestFailed(questID) then return nil end
  local m, x, y, level = ns.BlizzardQuestPoint(questID)
  if not m then return nil end
  if ns.IsQuestComplete(questID) then return m, x, y, "turnin", "blizzard", level end
  if AtUsePlaceWithoutItem(questID, m, x, y) then
    stats.skippedUse = stats.skippedUse + 1
    return nil
  end
  return m, x, y, "objective", "blizzard", level
end

-- Learn from Blizzard: a POI on a zone map for a quest with exactly one open
-- objective (no "use an item" objective, no escort or other event) that is far from every known point
-- of that objective becomes a learned spot (exportable like the others).
local function Near(p, m, x, y)
  return p.mapID == m and ((p.x - x) * 100) ^ 2 + ((p.y - y) * 100) ^ 2 < DIFF * DIFF
end

function Learn()
  if not ns.AddObjectiveSpot then return end
  for _, info in ipairs(ns.QuestLogEntries()) do
    local id = info.questID
    if not ns.IsQuestComplete(id) and not ns.IsQuestFailed(id) then
      local m, x, y, level = ns.BlizzardQuestPoint(id)
      local total, open, index, types = ns.ObjectiveState(id)
      -- not for escorts and other events: the POI may be the end of the escort
      if m and level == "zone" and total > 0 and open == 1 and index and not types.event
          and not ns.IsUseObjective(id, index) then
        local o = ns.ATT_OBJECTIVES and ns.ATT_OBJECTIVES[id] and ns.ATT_OBJECTIVES[id][index]
        local spots = ((ns.ObjectiveSpots and ns.ObjectiveSpots(id) or (ns.db.learnedObj or {})[id]) or {})[index]
        local known = false
        for _, p in ipairs(ns.ObjectiveTargets(id, index, o, spots)) do
          if Near(p, m, x, y) then known = true break end
        end
        if not known and ns.AddObjectiveSpot(id, index, m, x, y) then stats.learned = stats.learned + 1 end
      end
    end
  end
end

-- For /qd diag
function ns.POIDiag()
  local apis = {}
  for _, name in ipairs({ "GetQuestsOnMap", "GetNextWaypoint", "GetNextWaypointForMap", "IsOnMap",
      "GetQuestAdditionalHighlights" }) do
    apis[#apis + 1] = name .. " " .. (Fn(name) and "yes" or "no")
  end
  apis[#apis + 1] = "QuestPOIGetIconInfo " .. (type(QuestPOIGetIconInfo) == "function" and "yes" or "no")
  local entries = ns.QuestLogEntries()
  local n, levels = 0, { zone = 0, waypoint = 0, continent = 0 }
  local onMapN = 0
  for _, info in ipairs(entries) do
    local _, _, _, level = ns.BlizzardQuestPoint(info.questID)
    if level then n = n + 1 levels[level] = levels[level] + 1 end
    local isOn = Fn("IsOnMap")
    if isOn and ns.True(ns.Value(isOn, info.questID)) then onMapN = onMapN + 1 end
  end
  return table.concat(apis, ", "),
    ("%d of %d log quests (zone %d, waypoint %d, continent %d), IsOnMap %d, maps asked %d, use place skipped %d, learned from Blizzard %d"):format(
      n, #entries, levels.zone, levels.waypoint, levels.continent, onMapN, stats.maps, stats.skippedUse, stats.learned)
end

local function MarkDirty() dirty = true end
ns.On("QUEST_LOG_UPDATE", MarkDirty)
ns.On("QUEST_POI_UPDATE", MarkDirty)
ns.On("ZONE_CHANGED_NEW_AREA", MarkDirty)
ns.On("ZONE_CHANGED", MarkDirty)
ns.On("ZONE_CHANGED_INDOORS", MarkDirty)
ns.On("PLAYER_ENTERING_WORLD", MarkDirty)
ns.On("QUEST_TURNED_IN", MarkDirty)
ns.On("QUEST_ACCEPTED", MarkDirty)

-- Quests the client completes without a visit (QUEST_AUTOCOMPLETE): no
-- turn-in point, complete it from the quest log or the tracker popup.
local autoComplete = {}
ns.On("QUEST_AUTOCOMPLETE", function(_, questID)
  questID = ns.Num(questID)
  if questID then autoComplete[questID] = true end
end)
ns.On("QUEST_TURNED_IN", function(_, questID)
  questID = ns.Num(questID)
  if questID then autoComplete[questID] = nil end
end)
function ns.IsAutoComplete(questID)
  if autoComplete[questID] then return true end
  local index = ns.Num(ns.Value(C_QuestLog.GetLogIndexForQuestID, questID))
  local info = index and ns.Value(C_QuestLog.GetInfo, index)
  return type(info) == "table" and ns.True(info.isAutoComplete) or false
end
