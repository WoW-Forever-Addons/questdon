local _, ns = ...
local L = ns.L

-- World map pins: available quests (ATT + learned), learned turn-in points and
-- quest objective spawns (ATT). Our own data provider and pin templates only.
local QUEST_TEMPLATE = "QuestdonQuestPinTemplate"
local OBJECTIVE_TEMPLATE = "QuestdonObjectivePinTemplate"
local AREA_TEMPLATE = "QuestdonAreaPinTemplate"
local provider

-- A colour per quest, so the marks of different quests can be told apart. (20.10., Daniel) Quests in the log get
-- their own colour from 10 distinct ones (the least used one, kept per character in QuestdonCharDB.qcolors until the
-- quest leaves the log); other quests (available pins, areas) fall back to a colour by quest ID.
local COLORS = {
  { 0.35, 0.8, 1 }, { 1, 0.45, 0.3 }, { 0.6, 1, 0.4 }, { 0.9, 0.5, 1 }, { 1, 0.6, 0.8 },
  { 0.4, 0.5, 1 }, { 1, 0.7, 0.2 }, { 0.2, 0.85, 0.6 }, { 0.8, 0.6, 0.4 }, { 0.9, 0.2, 0.3 },
}
ns.QUEST_COLORS = COLORS
local function QuestColorIndex(questID)
  questID = tonumber(questID) or 0
  local store = ns.charDB and type(ns.charDB.qcolors) == "table" and ns.charDB.qcolors
  if ns.charDB and not store and ns.InQuestLog and ns.InQuestLog(questID) then
    store = {}
    ns.charDB.qcolors = store
  end
  if store then
    local i = store[questID]
    if i then return i end
    if ns.InQuestLog and ns.InQuestLog(questID) then
      -- forget what left the log, then take the least used colour (ties: the lowest)
      local used = {}
      for id, ci in pairs(store) do
        if ns.InQuestLog(id) then used[ci] = (used[ci] or 0) + 1 else store[id] = nil end
      end
      local best, bestN = 1, math.huge
      for ci = 1, #COLORS do
        local n = used[ci] or 0
        if n < bestN then best, bestN = ci, n end
      end
      store[questID] = best
      return best
    end
  end
  return questID % #COLORS + 1
end
ns.QuestColorIndex = QuestColorIndex
local function QuestColor(questID)
  local c = COLORS[QuestColorIndex(questID)]
  return c[1], c[2], c[3]
end
ns.QuestColor = QuestColor

-- (1.3) The game marks the turn-in of a finished quest itself (its quest
-- POI, a "?"): with the option "skipGameGivers" no second "?" from Questdon.
local function GameShowsTurnIn(questID)
  if not (ns.db and ns.db.skipGameGivers) or not ns.QuestPOI then return false end
  -- (07.11.2026) the game draws none of its round markers on the world map (ns.CheckGameQuestPins): Questdon draws the ?
  if ns.gameDrawsQuestPins == false then return false end
  -- (09.11.2026, Daniel near Thelsamar: "questdon zeigt einige quests nicht auf der weltmap an") the game draws its ?
  -- for some finished quests only: one it left out on the shown map (ns.CheckGameQuestPins) gets Questdon's ?
  if ns.gameMissesTurnIn and ns.gameMissesTurnIn[questID] then return false end
  -- (17.10., Daniel's screenshots of the three styles) with the game's markers taken off the world map its "?" goes
  -- too: Questdon draws the turn-in then
  -- (18.10., Daniel: "as the standard with our own symbols") the game's ? stays on the map with hideGamePOIs too, as
  -- long as its pins can be told apart (ns.gameKeepsTurnIns, see ClearGamePOIs); only when they cannot, Questdon draws it
  if ns.db.hideGamePOIs and ns.gameKeepsTurnIns == false then return false end
  local m, _, _, kind = ns.QuestPOI(questID)
  return m ~= nil and kind == "turnin"
end
ns.GameShowsTurnIn = GameShowsTurnIn

-- (07.11.2026, Daniel: "meine ? zum abgeben sind weg", Forever client build 70862) the game still reports its quests
-- on the map (C_QuestLog.GetQuestsOnMap, ns.QuestPOI says "turnin") but draws none of its round markers: Westfall with
-- three finished quests, 0 QuestPinTemplate pins. The shown map is counted shortly after Questdon drew it: finished
-- quests on it and not one of the game's pins means the game draws no ?, Questdon draws them
-- (ns.gameDrawsQuestPins = false); a game pin seen again sets it back (true), the game's ? as before. Per session.
-- (09.11.2026) also the quests of the pins: questID on each pin (QuestPinMixin), ids[questID] = true
local function GameQuestPinCount(map, ids)
  local pools = map and map.pinPools
  local pool = type(pools) == "table" and pools.QuestPinTemplate
  local n, tagged = 0, false
  if type(pool) == "table" and type(pool.activeObjects) == "table" then
    for pin in pairs(pool.activeObjects) do
      n = n + 1
      local id = type(pin) == "table" and ns.Num(pin.questID)
      if id then ids[id], tagged = true, true end
    end
  end
  return n, tagged
end
ns.gameMissesTurnIn = {}
-- (19.11.2026, Daniel: "dass Questdon die fertigen Quests auf der Weltkarte anzeigt. Nicht nur in der Zonenkarte")
-- the continent map shows the "?" of every finished quest of its zones too (TurnIns). ns.gameWideTurnIns: the quests
-- the game pins itself on the continent shown last (no second "?" there, option skipGameGivers).
local CONTINENT = 2 -- Enum.UIMapType.Continent
function ns.IsContinentMap(mapID)
  local info = mapID and C_Map and C_Map.GetMapInfo and ns.Value(C_Map.GetMapInfo, mapID)
  return type(info) == "table" and ns.Num(info.mapType) == CONTINENT
end
ns.gameWideTurnIns = { ids = {} }
-- (21.11.2026, Ruckler) what the game pinned is kept per continent (wideByMap): opening a continent seen before builds
-- with it at once, and a refresh follows only when the set really changed and the option uses it (skipGameGivers); every
-- opening and each switch of the continent built the map a second time 0.3 s later
local wideByMap = {}
local function WideKnown(mapID)
  local w = ns.gameWideTurnIns
  if w.map == mapID then return w.ids end
  return wideByMap[mapID]
end
ns.GameWideKnown = WideKnown
function ns.CheckGameQuestPins()
  local map = WorldMapFrame
  if not (map and map.IsShown and ns.True(ns.Value(map.IsShown, map))) then return end
  local mapID = ns.Num(ns.Value(map.GetMapID, map))
  if not mapID then return end
  -- (19.11.2026) a continent map: only which finished quests the game marks there itself (TurnIns); what it draws on
  -- a continent says nothing about the zone maps
  if ns.IsContinentMap(mapID) then
    local ids = {}
    GameQuestPinCount(map, ids)
    local old = WideKnown(mapID) or {}
    local same = true
    for id in pairs(ids) do if not old[id] then same = false break end end
    if same then for id in pairs(old) do if not ids[id] then same = false break end end end
    if ns.gameWideTurnIns.map ~= mapID or not same then
      ns.gameWideTurnIns = { map = mapID, ids = ids }
      wideByMap[mapID] = ids
    end
    if not same and ns.db.skipGameGivers and ns.QueueRefresh then ns.QueueRefresh("map") end
    return
  end
  local fn = C_QuestLog and C_QuestLog.GetQuestsOnMap
  if not mapID or type(fn) ~= "function" then return end
  local ok, list = pcall(fn, mapID)
  if not ok or type(list) ~= "table" then return end
  local v
  local ids = {}
  local n, tagged = GameQuestPinCount(map, ids)
  -- (09.11.2026) the game draws markers, but not for every finished quest (Thelsamar: one ? of several): with pins
  -- that carry their quest, a finished quest on this map without its pin gets Questdon's ? (ns.gameMissesTurnIn)
  local changed = false
  local listed = {} -- quests the game names for this map
  if n > 0 then v = true end
  for _, q in ipairs(list) do
    local id = type(q) == "table" and ns.Num(q.questID)
    if id then listed[id] = true end
    if id and ns.IsQuestComplete(id) and not ns.IsQuestFailed(id) then
      if n == 0 then v = false end
      local miss = (n > 0 and tagged and not ids[id]) or nil
      if ns.gameMissesTurnIn[id] ~= miss then ns.gameMissesTurnIn[id], changed = miss, true end
    end
  end
  -- (12.11.2026, Daniel in Redridge: Show of Force, grey at level 26 and ready, "?" on the minimap but not on the world
  -- map, "vielleicht weil die quest grau ist?") a finished quest the game does not list for this map at all got no check
  -- above, so its ? counted as the game's and nobody drew it. Every finished quest of the log whose turn-in we know on
  -- this map and that has no pin of the game is missed by the game. (The pins seen a moment later set it back.)
  if n == 0 or tagged then
    for _, info in ipairs(ns.QuestLogEntries()) do
      local id = ns.Num(info.questID)
      if id and not listed[id] and ns.IsQuestComplete(id) and not ns.IsQuestFailed(id)
          and ns.KnownTurnIn and ns.KnownTurnIn(id) == mapID then
        local miss = not ids[id] or nil
        if ns.gameMissesTurnIn[id] ~= miss then ns.gameMissesTurnIn[id], changed = miss, true end
      end
    end
  end
  if v ~= nil and ns.gameDrawsQuestPins ~= v then ns.gameDrawsQuestPins, changed = v, true end
  if changed and ns.QueueRefresh then ns.QueueRefresh("map") end
end

-- (19.11.2026, Daniel: "für den Fall Spiel Ausrufezeichen und Questdon Fragezeichen, wo das Ausrufezeichen liegt vom
-- Spiel") the game's own "!" (QuestOfferPinTemplate) and our "?" cannot share a marker: our "?" goes one frame level
-- above the highest "!" of the game on the shown map, so a turn-in is never under a "!". Read from the game's pins
-- once the map is drawn (nothing assumed about its levels); a pin used again gets its level back (QuestPin:OnAcquired).
function ns.RaiseTurnInPins()
  local pools = WorldMapFrame and WorldMapFrame.pinPools
  local offer = type(pools) == "table" and pools.QuestOfferPinTemplate
  local ours = type(pools) == "table" and pools[QUEST_TEMPLATE]
  if not (type(offer) == "table" and type(offer.activeObjects) == "table"
          and type(ours) == "table" and type(ours.activeObjects) == "table") then return 0 end
  local top
  for pin in pairs(offer.activeObjects) do
    local lv = type(pin) == "table" and ns.Num(ns.Value(pin.GetFrameLevel, pin))
    if lv and (not top or lv > top) then top = lv end
  end
  if not top then return 0 end
  local n = 0
  for pin in pairs(ours.activeObjects) do
    local p = type(pin) == "table" and pin.qdPin
    if type(p) == "table" and p.kind == "turnin" and pin.SetFrameLevel then
      local lv = ns.Num(ns.Value(pin.GetFrameLevel, pin))
      if lv and lv <= top and pcall(pin.SetFrameLevel, pin, top + 1) then
        pin.qdLevelWas = pin.qdLevelWas or lv
        n = n + 1
      end
    end
  end
  return n
end

-- (1.3.5, Daniel 10.10.) The "?" of a finished quest: not only where you turned it in before,
-- also what other players reported and the turn-in NPC of the data (ns.KnownTurnIn), as long as
-- the game does not mark the turn-in itself. Quests that complete from the log get none.
-- (19.11.2026, CurseForge Neidhardt: "the exclamation mark icon was covering the question mark") second list: the
-- turn-ins the game marks itself (gameToo). Where Questdon draws a "!" at that spot, its marker takes them in
-- (BuildBase, ns.GroupQuestPins), else the game's "?" lay under our "!"
local function TurnIns(mapID)
  local list, game = {}, {}
  if not ns.db.learnPins then return list, game end
  local wide = ns.IsContinentMap(mapID)
  local gameWide = wide and ns.db.skipGameGivers and WideKnown(mapID) or {}
  for _, info in ipairs(ns.QuestLogEntries()) do
    local questID = info.questID
    if ns.IsQuestComplete(questID) and not (ns.IsAutoComplete and ns.IsAutoComplete(questID))
        and not (ns.db.pinsOnlyUnknown and ns.QuestieOn() and ns.QuestieKnows(questID) == true and ns.QuestieDrawsMarks("turnin")) -- (review 1) only while Questie draws
        then
      local m, x, y, npc, source, npcID = ns.KnownTurnIn(questID)
      if wide and m and m ~= mapID and x and y then
        -- the zone's point on the continent, through the world position; nil on another continent or in an instance
        local c, n, w = ns.WorldPos(m, x, y)
        local wx, wy
        if c then wx, wy = ns.MapFromWorld(mapID, c, n, w) end
        if wx and wy and wx >= 0 and wx <= 1 and wy >= 0 and wy <= 1 and not gameWide[questID] then
          list[#list + 1] = { kind = "turnin", questID = questID, x = wx, y = wy, npc = npc, source = source, npcID = npcID, zoneMap = m, zx = x, zy = y }
        end
      elseif m == mapID and x and y then
        local t = { kind = "turnin", questID = questID, x = x, y = y, npc = npc, source = source, npcID = npcID }
        if GameShowsTurnIn(questID) then t.gameToo = true game[#game + 1] = t else list[#list + 1] = t end
      end
    end
  end
  return list, game
end

-- Everything for one map (also used by the tests).
-- (1.23) Once per map and scope: the world map and the minimap of the same
-- zone share it in the batched refresh. Callers only read the list.
-- (1.3.5) ns.PinsForMapBase: the same without the objective dots (the minimap takes its own).
local BuildPins, BuildBase
function ns.PinsForMap(mapID)
  return ns.Memo("pins", mapID, BuildPins)
end
-- pause: (24.11.2026, Ruckler Runde 4) the builds in slices of the map and the minimap: given on to the engine
-- (ns.AvailableQuestsOnMap, ns.ObjectivePointsOnMap; an engine without it leaves it out) and called between the parts
function ns.PinsForMapBase(mapID, pause)
  return ns.Memo("pinsBase", mapID, BuildBase, pause)
end
-- pause: (24.11.2026) the map's refresh in slices (RefreshIfChanged below) pauses between the base and the dots
function BuildPins(mapID, pause)
  local pins = {}
  if not mapID then return pins end
  for _, p in ipairs(ns.PinsForMapBase(mapID, pause)) do pins[#pins + 1] = p end
  if pause then pause("dots") end
  if ns.db.objectivePins then
    for _, o in ipairs(ns.ObjectivePointsOnMap(mapID, pause)) do
      o.kind = "objective"
      pins[#pins + 1] = o
    end
  end
  return pins
end
-- (06.11.2026) OpenMap's stitched world map is up: it shows the dungeon entrances itself (OpenMapAPI.IsStitched)
local lastOpenMap = false
function ns.OpenMapEntrances()
  local api = rawget(_G, "OpenMapAPI")
  if type(api) ~= "table" or type(api.IsStitched) ~= "function" then return false end
  local ok, on = pcall(api.IsStitched)
  return ok and on == true
end

function BuildBase(mapID, pause)
  local pins = {}
  if not mapID then return pins end
  if ns.db.availablePins then
    for i, a in ipairs(ns.AvailableQuestsOnMap(mapID, pause)) do
      if not ns.DrawnElsewhere(a.questID, "start") then
        a.kind = "available"
        pins[#pins + 1] = a
      end
      if pause and i % 32 == 0 then pause() end
    end
  end
  if pause then pause() end
  local own, game = TurnIns(mapID)
  if pause then pause() end
  for _, t in ipairs(game) do
    -- only where one of our "!" stands at its spot (the marker then shows the "?"); alone it stays the game's
    for _, a in ipairs(pins) do
      if a.kind == "available" and a.x and a.y and ns.TurnInJoins(a, t) then pins[#pins + 1] = t break end
    end
  end
  for _, t in ipairs(own) do pins[#pins + 1] = t end
  -- (1.2) the quest picked in the zone quest list (ZoneQuests.lua)
  local focus = ns.ZoneFocusPin and ns.ZoneFocusPin(mapID)
  if focus then pins[#pins + 1] = focus end
  -- (1.3.5) a marked dungeon entrance (Dungeons.lua), and the entrances of all dungeons
  local entrance = ns.EntrancePin and ns.EntrancePin(mapID)
  if entrance then pins[#pins + 1] = entrance end
  -- (10.11.2026) the waypoint of /way (Way.lua)
  for _, way in ipairs(ns.WayPins and ns.WayPins(mapID) or {}) do pins[#pins + 1] = way end
  for _, d in ipairs(ns.DungeonEntrancePins and ns.DungeonEntrancePins(mapID) or {}) do pins[#pins + 1] = d end
  return pins
end

local function GiverText(pin)
  if pin.npc then return pin.npc end
  if pin.kind == "turnin" then return nil end -- (1.3.5) never the quest giver for a turn-in
  local givers = ns.QuestGiverIDs(pin.questID)
  local name = givers and ns.LocalNpcName(givers[1])
  return name
end

-- (1.21) Quest givers with several quests. Available quests that start at
-- the same spot (closer than GROUP_DIST in 0-1 map coordinates, about the
-- size of a pin) used to stack: only the top pin could be hovered. Now they
-- become one pin with pin.group = { pins, sorted by level }. The pin list of
-- ns.PinsForMap (API, signature) stays one entry per quest; only the display
-- (world map, minimap) groups. Turn-ins and objective dots are never grouped.
-- (1.25) Two nearly overlapping "!" for one quest giver: a start Questdon
-- learned is where the player stood when talking (a few yards off the NPC),
-- the data has the NPC's own spot, and two NPCs can stand side by side.
-- Pins of the same quest giver (creature ID from the data or the learned
-- start) now group up to GIVER_DIST apart, any two up to GROUP_DIST as before.
local GROUP_DIST, GIVER_DIST = 0.004, 0.015
local dupStats = { merged = 0, lastMerged = 0, suppressed = 0, lastSuppressed = 0 }
local function MinLevel(questID)
  return ns.QuestLevel(questID) or 0
end
-- Creature IDs of the quest giver(s) of a pin: learned start NPC, else the data.
-- (pin lists are never changed after they are built: a weak cache instead of a field)
local giverCache = setmetatable({}, { __mode = "k" })
local function GiverIDs(p)
  local ids = giverCache[p]
  if ids == nil and p.kind == "turnin" then
    -- (16.10.) a turn-in stands at its turn-in NPC, not at the quest's giver
    ids = p.npcID and { p.npcID } or false
    giverCache[p] = ids
  elseif ids == nil then
    local e = ns.db.learned and ns.db.learned[p.questID]
    local npc = e and e.start and not e.start.item and ns.Num(e.start.npcID)
    ids = npc and { npc } or ns.QuestGiverIDs(p.questID) or false
    giverCache[p] = ids
  end
  return ids or nil
end
local function SameGiver(a, b)
  local ga, gb = GiverIDs(a), GiverIDs(b)
  if not (ga and gb) then return false end
  for _, x in ipairs(ga) do
    for _, y in ipairs(gb) do if x == y then return true end end
  end
  return false
end
-- One spot for display: close together, or the same quest giver a bit apart.
-- cluster: markers closer than this would overlap on screen and merge too (world map: ns.ClusterDistance)
local function SameSpot(a, b, cluster)
  local dx, dy = math.abs(a.x - b.x), math.abs(a.y - b.y)
  if dx < GROUP_DIST and dy < GROUP_DIST then return true, false end
  if dx < GIVER_DIST and dy < GIVER_DIST and SameGiver(a, b) then return true, true end
  if cluster and dx < cluster and dy < cluster then return true, false end
  return false, false
end
ns.SameQuestGiverSpot = SameSpot
-- A turn-in and a quest marker in one marker: the same NPC a bit apart, or (19.11.2026) the very same spot, where
-- one symbol hides the other whoever stands there (a turn-in whose NPC is not known)
local function TurnInJoins(a, b)
  local dx, dy = math.abs(a.x - b.x), math.abs(a.y - b.y)
  if dx < GROUP_DIST and dy < GROUP_DIST then return true end
  return dx < GIVER_DIST and dy < GIVER_DIST and SameGiver(a, b)
end
ns.TurnInJoins = TurnInJoins
function ns.GroupQuestPins(pins, cluster)
  local out, heads, dropped = {}, {}, false
  dupStats.lastMerged = 0
  for _, p in ipairs(pins or {}) do
    local head
    -- (16.10., Daniel's Undead start: no "?" for Vital Intelligence in Brill) a turn-in at an NPC who also offers
    -- quests joins their marker: drawn apart, the "!" lay on top of the "?" (same spot, same frame level)
    -- (only at the same NPC: a turn-in next to another giver stays its own "?")
    local joins = (p.kind == "available" or p.kind == "turnin") and p.x and p.y
    if joins then
      for _, h in ipairs(heads) do
        local same, byGiver
        if p.kind == "turnin" or h.pin.kind == "turnin" then
          for _, m in ipairs(h.members) do
            if TurnInJoins(m, p) then same = true break end
          end
        else
          same, byGiver = SameSpot(h.pin, p, cluster)
        end
        if same then
          head = h
          if byGiver then dupStats.merged = dupStats.merged + 1 dupStats.lastMerged = dupStats.lastMerged + 1 end
          break
        end
      end
    end
    if head then
      head.members[#head.members + 1] = p
    elseif joins then
      local entry = { pin = p, members = { p }, x = p.x, y = p.y, isEntry = true }
      heads[#heads + 1] = entry
      out[#out + 1] = entry
    else
      out[#out + 1] = p -- (16.10., stutter report) dots as they are: two new tables each before
    end
  end
  for i, e in ipairs(out) do
    if not e.isEntry then
      -- a pin passed through (also an objective bundle, which has members of its own)
    elseif #e.members == 1 then
      out[i] = e.pin
      if e.pin.gameToo then out[i], dropped = false, true end -- (19.11.2026) alone it is the game's "?": no second one
    else
      table.sort(e.members, function(a, b)
        -- (16.10.) the turn-ins first: the marker shows the "?" of what is ready to hand in
        local ta, tb = a.kind == "turnin", b.kind == "turnin"
        if ta ~= tb then return ta end
        local la, lb = MinLevel(a.questID), MinLevel(b.questID)
        if la ~= lb then return la < lb end
        return a.questID < b.questID
      end)
      -- a copy: the original pins stay untouched (signature, precomputed list)
      local g = {}
      for k, v in pairs(e.members[1]) do g[k] = v end
      g.group = e.members
      out[i] = g
      -- only turn-ins the game marks itself: its "?" stand there already
      local all = true
      for _, m in ipairs(e.members) do if not m.gameToo then all = false break end end
      if all then out[i], dropped = false, true end
    end
  end
  if dropped then
    local kept = {}
    for _, e in ipairs(out) do if e then kept[#kept + 1] = e end end
    out = kept
  end
  return out
end

-- (1.25) Quests the game itself shows as available (its quest lines list
-- them with a spot): the modern client draws its own "!" for them, so a
-- Questdon "!" there is a second one. With the option "skipGameGivers" (on
-- by default) Questdon leaves such quest givers to the game: the quest and
-- every other available pin at the same giver are not drawn (world map and
-- minimap). Panel, nameplates and unit tooltips keep them.
-- (1.3.3) Daniel 08.10., Zephras Isle: a Questdon "!" still stood next to the
-- game's one. The game draws at the spot of its quest lines (pin.gx/gy), which
-- can lie a little off the data's spot of the same quest; our other quests of
-- that giver were compared with the data's spot only and, with the tiny
-- distance, stayed. Now both spots count, with the overlap distance of the map.
function ns.SkipGameShownPins(pins, dist)
  local n = 0
  if not (ns.db and ns.db.skipGameGivers) then dupStats.lastSuppressed = 0 return pins or {}, 0 end
  local game = {}
  for _, p in ipairs(pins or {}) do
    if p.kind == "available" and p.gameShown and p.x and p.y then
      game[#game + 1] = p
      if p.gx and p.gy then game[#game + 1] = { kind = "available", questID = p.questID, x = p.gx, y = p.gy } end
    end
  end
  if #game == 0 then dupStats.lastSuppressed = 0 return pins or {}, 0 end
  local out = {}
  for _, p in ipairs(pins) do
    local drop = false
    if p.kind == "available" and p.x and p.y then
      if p.gameShown then
        drop = true
      else
        for _, g in ipairs(game) do
          if SameSpot(g, p, dist) then drop = true break end
        end
      end
    end
    if drop then n = n + 1 else out[#out + 1] = p end
  end
  dupStats.suppressed = dupStats.suppressed + n
  dupStats.lastSuppressed = n
  return out, n
end

-- (1.25) What the world map and the minimap draw: game-drawn givers left
-- out, the rest grouped per quest giver.
function ns.DisplayQuestPins(pins, cluster)
  return ns.GroupQuestPins((ns.SkipGameShownPins(pins, cluster)), cluster)
end

-- (1.3.3) Daniel 08.10., Zephras Isle: its quest givers stand 0.2 to 0.8 map
-- units apart (0.002-0.008), so their "!" covered each other although none of
-- them shared a giver. Markers that would overlap on screen always merge (OVERLAP_DIST, 0-1 map coordinates).
-- (10.11.2026, Daniel: dead functions out) the option "Merge markers" (1.28, clusterPins: a wider distance that
-- followed the map's zoom) is gone: off for everybody since 28.10.2026 and without a switch. The world map merges at
-- the fixed distance, as it did with the option off; the zoom steps below serve the objective dots.
local OVERLAP_DIST = 0.012
ns.MINIMAP_OVERLAP = 0.01 -- minimap: a fixed distance (about one marker at its usual zoom)
function ns.ClusterBucket(scale)
  scale = ns.Num(scale)
  if not scale or scale < 1 then return 1 end
  if scale > 8 then scale = 8 end
  return math.floor(scale * 2 + 0.5) / 2
end
function ns.ClusterDistance(scale)
  return OVERLAP_DIST / ns.ClusterBucket(scale)
end
function ns.DuplicatePinStats() return dupStats end

-- (1.21) Title of a grouped pin: the quest giver if all quests share it,
-- else "n quests here".
local function GroupTitle(pin)
  local name
  for i, p in ipairs(pin.group) do
    local giver = GiverText(p)
    if i == 1 then name = giver elseif giver ~= name then name = nil end
    if not name then break end
  end
  return name or L["%d quests here"]:format(#pin.group)
end
ns.QuestGroupTitle = GroupTitle

-- (1.26) How many levels below yours a quest is still green (not grey): the
-- client's own answer (UnitQuestTrivialLevelRange, in the Forever API
-- documentation), else the older GetQuestGreenRange, else 8.
function ns.QuestTrivialRange()
  local r = ns.Num(ns.Value(UnitQuestTrivialLevelRange, "player")) or ns.Num(ns.Value(GetQuestGreenRange))
  if r and r >= 0 then return r end
  return 8
end

-- (1.17) Difficulty colour for a quest level against the player level, own
-- rules (no Blizzard helper): red +5, orange +3, yellow +-2, green inside the
-- green range, grey below.
-- (18.11.2026, player's picture: Blizzard's list green, ours grey) for your own level the game's colour decides
-- (DonCore Kit.QuestDifficulty asks GetQuestDifficultyColor); the codes stay ours, grey stays |cff808080.
local LEVEL_CODE = { impossible = "|cffff2020", verydifficult = "|cffff8040", difficult = "|cffffff00",
  standard = "|cff40c040", trivial = "|cff808080" }
function ns.LevelColor(level, player)
  -- (23.11.2026) always the same answer as our quest list (Tracker.lua LevelRGB: Kit.QuestDifficulty), also where a
  -- client has no GetQuestDifficultyColor (Forever has it: at 20 it calls 14 grey, trivial range 5)
  if player == nil and ns.Num(level) then
    local Kit = LibStub and LibStub("DonCore-1.0", true)
    Kit = Kit and Kit.Get and Kit:Get("Kit", 28)
    local code = Kit and LEVEL_CODE[Kit.QuestDifficulty(level)]
    if code then return code end
  end
  player = player or ns.PlayerLevel()
  if not (ns.Num(level) and ns.Num(player)) then return "|cffffffff" end
  local d = level - player
  if d >= 5 then return "|cffff2020" end
  if d >= 3 then return "|cffff8040" end
  if d >= -2 then return "|cffffff00" end
  if d >= -ns.QuestTrivialRange() then return "|cff40c040" end
  return "|cff808080"
end

-- (23.11.2026, Daniel: the card's "[14] The People's Militia" grey, Blizzard's quest list beside the map green; "wenn
-- möglich von forever auslesen lassen") Blizzard's list colours a quest by what the game says about that quest, not
-- by its level: C_PlayerInfo.GetContentDifficultyQuestForPlayer (in the game at 20: quest 13 [14] gives 1 = easy,
-- green, while GetQuestDifficultyColor(14) gives grey). Enum.RelativeContentDifficulty: 0 trivial, 1 easy, 2 fair,
-- 3 difficult, 4 impossible. Without it (Classic Era) the colour by level.
local CONTENT_KEY = { [0] = "trivial", [1] = "standard", [2] = "difficult", [3] = "verydifficult", [4] = "impossible" }
-- the game's difficulty of a quest as a Kit quest key (the quest list uses it too), nil without the API
function ns.QuestContentKey(questID)
  local api = C_PlayerInfo and C_PlayerInfo.GetContentDifficultyQuestForPlayer
  local d = api and ns.Num(questID) and ns.Num(ns.Value(api, questID))
  return d and CONTENT_KEY[d] or nil
end
function ns.QuestLevelColor(questID, level)
  local key = ns.QuestContentKey(questID)
  if key then return LEVEL_CODE[key] end
  return ns.LevelColor(level)
end

-- (1.17) Where the start point of an available quest comes from:
-- "game" (the client's quest lines), "learned" (Questdon saw it) or "database" (ATT).
function ns.StartSource(questID)
  local e = ns.db.learned[questID]
  if e and e.start and not e.start.item then
    return e.start.source == "blizzard" and "game" or "learned"
  end
  return "database"
end

local SOURCE_TEXT = {
  game = L["Location: from the game (quest lines)"],
  learned = L["Location: learned by Questdon"],
  database = L["Location: database (All The Things)"],
}

-- (1.24) Who confirmed that the quest is available.
local AVAILABLE_TEXT = {
  game = L["Available: confirmed by the game"],
  npc = L["Available: confirmed by the quest giver"],
  database = L["Available: only the data says so (not confirmed)"],
}
local AVAILABLE_SHORT = {
  game = L["confirmed by the game"],
  npc = L["confirmed by the quest giver"],
  database = L["data only, not confirmed"],
}
ns.AVAILABLE_SHORT = AVAILABLE_SHORT

-- (1.17) Tooltip text of a quest start / turn-in pin (also used by the tests).
function ns.QuestPinDescription(pin)
  local desc
  if pin.kind == "turnin" then
    desc = L["Turn in here"]
    local rewards = ns.QuestRewardLines and ns.QuestRewardLines(pin.questID) or {}
    if #rewards > 0 then desc = desc .. "\n" .. table.concat(rewards, "\n") end
  elseif pin.learned then
    desc = L["Quest available (learned by Questdon)"]
  else
    desc = L["Quest available"]
  end
  local function Add(line) desc = desc .. "\n" .. line end
  if pin.kind ~= "turnin" then
    -- (1.22) an unknown level is said, never guessed
    local level = ns.ShownQuestLevel(pin.questID)
    if level then Add(ns.QuestLevelColor(pin.questID, level) .. L["Level %d"]:format(level) .. "|r")
    else Add("|cff737880" .. L["Level unknown"] .. "|r") end
  end
  local giver = GiverText(pin)
  if giver then Add(L["Quest giver: %s"]:format(giver)) end
  if pin.kind ~= "turnin" then
    local follow = #(ns.FollowUpQuests and ns.FollowUpQuests(pin.questID) or {})
    if follow == 1 then Add(L["Starts a chain: 1 follow-up quest known"])
    elseif follow > 1 then Add(L["Starts a chain: %d follow-up quests known"]:format(follow)) end
    -- (24.10.) where in a plain chain this quest stands ("step 2 of 3"), when there is a quest before it
    local step, total
    if ns.ChainPosition then step, total = ns.ChainPosition(pin.questID) end
    if step and step > 1 then Add(L["Chain: step %d of %d"]:format(step, total)) end
  end
  if ns.QuestFlags(pin.questID):find("b", 1, true) then Add(L["Breadcrumb quest"]) end
  -- (1.18) dungeon quest: name of the dungeon (Forever pays these quests extra XP)
  local dungeon = ns.QuestDungeon and ns.QuestDungeon(pin.questID)
  if dungeon then Add("|cff66ccff" .. L["Dungeon quest: %s"]:format(ns.DungeonName(dungeon)) .. "|r") end
  -- (1.18) group members with this quest (dungeon quests cannot be shared since beta 2026-09-24)
  local who = pin.kind ~= "turnin" and ns.PartyNamesText and ns.PartyNamesText(pin.questID) or {}
  if #who > 0 then Add("|cff99ccff" .. L["Your group has it: %s"]:format(table.concat(who, ", ")) .. "|r") end
  if pin.kind ~= "turnin" and ns.IsItemStartQuest(pin.questID) then
    Add(L["Starts from an item (drop or object nearby)"])
  end
  if pin.kind ~= "turnin" then Add("|cff999999" .. SOURCE_TEXT[ns.StartSource(pin.questID)] .. "|r") end
  -- (1.24) who says it is available: the game, a quest giver or only the data
  if pin.kind ~= "turnin" then
    Add("|cff999999" .. AVAILABLE_TEXT[ns.AvailabilitySource(pin.questID)] .. "|r")
  end
  -- (1.21) grouped pin: the other quests of this quest giver
  if pin.group and #pin.group > 1 then
    Add(L["Also here:"])
    for i = 2, #pin.group do Add("  " .. ns.QuestTitle(pin.group[i].questID)) end
  end
  return desc
end

-- (1.1) Hint of a quest pin: Alt-click reports "no quest here" (not for turn-ins).
-- (1.3.4) One short grey line; Shift shows the details (where the data comes from).
local function Details() return ns.True(ns.Value(IsShiftKeyDown)) end
ns.TooltipDetails = Details
function ns.QuestPinHint(pin)
  -- (review 7) a giver's marker with a turn-in in it (kind "turnin") still has quests to report
  local offers = pin and pin.kind ~= "turnin"
  if pin and not offers and pin.group then
    for _, m in ipairs(pin.group) do if m.kind ~= "turnin" then offers = true break end end
  end
  -- (07.11.2026, Daniel: Alt-click in the tooltip, clearer) says what Alt-click is for
  local hint = (offers and ns.ReportPin) and L["Click: arrow, Alt-click: no quest here, hide"] or L["Click: arrow"]
  if offers and not Details() then hint = hint .. ", " .. L["Shift: details"] end
  return hint
end

-- (1.3.4) Pressing or releasing Shift over a marker redraws its tooltip (details).
local hover = { owner = nil, fn = nil }
function ns.SetHoverTooltip(owner, fn) hover.owner, hover.fn = owner, owner and fn or nil end
ns.On("MODIFIER_STATE_CHANGED", function(_, key) -- (Questdon review 1) the event name comes first
  if not (hover.owner and hover.fn) then return end
  if type(key) == "string" and not key:find("SHIFT", 1, true) then return end
  local tt = GameTooltip
  local ok, owned = pcall(tt and tt.IsOwned or function() return false end, tt, hover.owner)
  if ns.PinCardOwned and ns.PinCardOwned(hover.owner) then ok, owned = true, true end -- (1.3.6) our hover card
  if ok and owned then ns.SafeCall("tooltip details", hover.fn, hover.owner) else hover.owner, hover.fn = nil, nil end
end)

-- (1.3.4) Daniel 08.10.: the level belongs in the title, "[6] Al'Aketh Assassins",
-- in the difficulty colour; "[?]" when the data has none (said, never guessed).
-- (23.11.2026, Daniel with the card "9 The People's Militia" beside the list's "[14]": "das questlevel sollte sich an
-- blizzards orientieren, nicht wann ich das annehmen kann") the level the game shows (quest log, kept, players'
-- logs: ns.GameQuestLevel), else the data's level you may take it at
function ns.ShownQuestLevel(questID)
  return ns.GameQuestLevel and ns.GameQuestLevel(questID) or ns.QuestLevel(questID)
end

function ns.LevelTitle(questID)
  local level = ns.ShownQuestLevel(questID)
  local tag = level and (ns.QuestLevelColor(questID, level) .. "[" .. level .. "]|r ") or "|cff737880[?]|r "
  return tag .. ns.QuestTitle(questID)
end

-- (1.1) "level 5, 6 (hidden after 3)"
function ns.NotHereLevelText(levels)
  local parts = {}
  for _, lv in ipairs(levels) do parts[#parts + 1] = tostring(lv) end
  return L["level %s (hidden after %d)"]:format(table.concat(parts, ", "), ns.NOT_HERE_LEVELS or 3)
end

-- (1.19) Quest pin tooltip in the family structure: title, key/value lines,
-- hint last (rendered with Style.Tooltip). Returns title, lines, hint.
local SOURCE_SHORT = {
  game = L["from the game (quest lines)"],
  learned = L["learned by Questdon"],
  database = L["database (All The Things)"],
}
-- questID given: the colour the game gives that quest (ns.QuestLevelColor); else by level (creatures)
local function LevelRGB(level, questID)
  local code = questID and ns.QuestLevelColor(questID, level) or ns.LevelColor(level)
  local r, g, b = code:match("|cff(%x%x)(%x%x)(%x%x)")
  if not r then return nil end
  return { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255 }
end

function ns.QuestPinTooltip(pin)
  local lines = {}
  local function KV(label, value, color) lines[#lines + 1] = { label, value, color } end
  -- (1.2) the quest picked in the zone quest list: its status there
  if pin.kind == "focus" then
    KV(L["Status"], pin.statusText or "")
    local level = ns.ShownQuestLevel(pin.questID)
    if level then KV(L["Level"], level, LevelRGB(level, pin.questID)) else KV(L["Level"], L["unknown"], "textHint") end
    local giver = GiverText(pin)
    if giver then KV(L["Quest giver"], giver) end
    return ns.QuestTitle(pin.questID), lines, L["Picked in the quest list of the zone."]
  end
  -- (1.3.4) Daniel 08.10.: compact. The "!" already says "quest available" and the
  -- title carries the level; source and confirmation only with Shift held.
  local details = Details()
  -- (19.11.2026, CurseForge Neidhardt: "if I hold Shift while hovering over an unaccepted quest ... it shows the quest
  -- objectives before I accept it") what the quest asks for (Data/Quest_Texts.lua), first, with Shift only
  if details and pin.kind ~= "turnin" then
    local text = ns.QuestText and ns.QuestText(pin.questID)
    if type(text) == "table" and type(text.o) == "string" and text.o ~= "" then
      lines[#lines + 1] = "|cffdcc17f" .. L["Objective"] .. ":|r " .. text.o
    end
  end
  -- (23.11.2026, Daniel: objective pins and quest givers alike) what the quest asks you to kill or collect, with
  -- picture and the creatures' level
  if pin.kind ~= "turnin" and ns.GiverObjectiveEntries then
    for _, e in ipairs(ns.GiverObjectiveEntries(pin.questID)) do lines[#lines + 1] = e end
  end
  if pin.kind == "turnin" then
    -- (1.3.6) the card's "?" and green stripe say "turn in here"; the line stays only when nothing else follows
    for _, r in ipairs(ns.QuestRewardLines and ns.QuestRewardLines(pin.questID) or {}) do KV(L["Reward"], r) end
  end
  local giver = GiverText(pin)
  if giver then KV(pin.kind == "turnin" and L["Turn in"] or L["Quest giver"], giver) end -- (1.3.5) the turn-in NPC as such
  -- (1.3.6, Daniel) an NPC that walks around: look nearby
  if ns.QuestNpcWalks and ns.QuestNpcWalks(pin.questID, pin.kind == "turnin") then lines[#lines + 1] = L["Walks around: look nearby"] end
  if pin.kind ~= "turnin" then
    local follow = #(ns.FollowUpQuests and ns.FollowUpQuests(pin.questID) or {})
    if follow > 0 then KV(L["Chain"], L["%d follow-up quests known"]:format(follow)) end
    local step, total
    if ns.ChainPosition then step, total = ns.ChainPosition(pin.questID) end
    if step and step > 1 then lines[#lines + 1] = L["Chain: step %d of %d"]:format(step, total) end
  end
  if ns.QuestFlags(pin.questID):find("b", 1, true) then lines[#lines + 1] = L["Breadcrumb quest"] end
  local dungeon = ns.QuestDungeon and ns.QuestDungeon(pin.questID)
  if dungeon then KV(L["Dungeon"], ns.DungeonName(dungeon), "accent") end
  local who = pin.kind ~= "turnin" and ns.PartyNamesText and ns.PartyNamesText(pin.questID) or {}
  if #who > 0 then KV(L["Your group has it"], table.concat(who, ", "), "good") end
  if pin.kind ~= "turnin" and ns.IsItemStartQuest(pin.questID) then
    lines[#lines + 1] = L["Starts from an item (drop or object nearby)"]
  end
  -- (1.1) levels at which the quest giver did not offer it (hidden after 3)
  local refused = pin.kind ~= "turnin" and ns.NotHereLevels and ns.NotHereLevels(pin.questID)
  if refused then KV(L["Not offered at"], ns.NotHereLevelText(refused), "textHint") end
  if pin.kind ~= "turnin" then
    local src = ns.AvailabilitySource(pin.questID)
    if details then
      KV(L["Location"], SOURCE_SHORT[ns.StartSource(pin.questID)])
      if src then KV(L["Available"], AVAILABLE_SHORT[src], src == "database" and "textHint" or "good") end
    elseif src == "database" then
      -- (1.24) only the data says so: one small line instead of two
      lines[#lines + 1] = "|cff737880" .. L["Not confirmed yet"] .. "|r"
    end
  end
  -- (20.10.) a hint for the way (Data/Quest_Hints.lua)
  local wayHint = ns.QuestHint and ns.QuestHint(pin.questID)
  if wayHint then lines[#lines + 1] = "|cffdcc17f" .. L["Hint"] .. ":|r " .. wayHint end
  if pin.kind == "turnin" and #lines == 0 then lines[1] = L["Turn in here"] end
  return ns.LevelTitle(pin.questID), lines, ns.QuestPinHint(pin)
end

-- (1.21) Tooltip of a grouped quest giver pin: one line per quest (title,
-- level in difficulty colour), below it dungeon and group if known. At most
-- GROUP_LINES quests, then "and n more".
local GROUP_LINES = 10
function ns.QuestGroupTooltip(pin)
  local lines = {}
  local group = pin.group or { pin }
  local details = Details()
  for i, p in ipairs(group) do
    if i > GROUP_LINES then
      lines[#lines + 1] = L["and %d more"]:format(#group - GROUP_LINES)
      break
    end
    -- (1.3.4) "[6] Title" like the single tooltip; a status only when there is one
    -- (23.11.2026) the whole title in its level colour, like the game's quest list
    local title = ns.ColoredLevelTitle and ns.ColoredLevelTitle(p.questID) or ns.LevelTitle(p.questID)
    if ns.QuestFlags(p.questID):find("b", 1, true) then title = title .. " (" .. L["Breadcrumb quest"] .. ")" end
    if p.kind == "turnin" then
      lines[#lines + 1] = { title, L["Turn in here"], "good" } -- (16.10.) a turn-in in the giver's marker
    else
      lines[#lines + 1] = { title }
      -- (19.11.2026) with Shift: what each quest asks for
      local text = details and ns.QuestText and ns.QuestText(p.questID)
      if type(text) == "table" and type(text.o) == "string" and text.o ~= "" then
        lines[#lines + 1] = "   |cffb0b4bc" .. text.o .. "|r"
      end
    end
    local dungeon = ns.QuestDungeon and ns.QuestDungeon(p.questID)
    if dungeon then lines[#lines + 1] = { "   " .. L["Dungeon"], ns.DungeonName(dungeon), "accent" } end
    local who = ns.PartyNamesText and ns.PartyNamesText(p.questID) or {}
    if #who > 0 then lines[#lines + 1] = { "   " .. L["Your group has it"], table.concat(who, ", "), "good" } end
  end
  return GroupTitle(pin), lines, ns.QuestPinHint(pin)
end

-- Small square in the quest's dot colour (texture escape with vertex colour).
local function Swatch(questID)
  local r, g, b = QuestColor(questID)
  return ("|TInterface\\Buttons\\WHITE8x8:8:8:0:0:8:8:0:8:0:8:%d:%d:%d|t "):format(r * 255, g * 255, b * 255)
end

---------------------------------------------------------------------------
-- (23.11.2026, Daniel with the objective cards: "den questnamen im pin anhand der farbzuweisung von blizzard ...
-- und den fortschrittsbalken? den '4 objectives spots' würde ich weglassen ... vll noch was mit einem kleinen bild?
-- wie dungeonkarte?", chosen: objective pins and quest givers) Each objective is an entry of the card
-- (PinCard.lua): a small picture (the creature's model, an item's icon), its name, the creatures' level range in
-- their difficulty colour, below it a progress bar in the quest's dot colour. Levels and models: DonData
-- Spawns.lua ns.SPAWN_MOBS (CMaNGOS); Forever's new creatures have none, then no level and the plain icon.
---------------------------------------------------------------------------
local MOB_ICON, OBJECT_ICON, ITEM_ICON = "Interface\\Icons\\INV_Sword_04", "Interface\\Icons\\INV_Misc_Gear_01", 134400
local MAX_GIVER_ENTRIES = 3

-- The quest's title in its level colour with the level, for headings inside a card.
function ns.ColoredLevelTitle(questID)
  local level = ns.ShownQuestLevel(questID)
  if not level then return "|cff737880[?]|r " .. ns.QuestTitle(questID) end
  return ns.QuestLevelColor(questID, level) .. "[" .. level .. "] " .. ns.QuestTitle(questID) .. "|r"
end

-- creatures (ids) -> lowest level, highest level, elite, model of the first known, first creature
local function MobRange(creatures)
  local lo, hi, elite, model, first
  for _, c in ipairs(creatures or {}) do
    c = ns.Num(c)
    if c then
      first = first or c
      local m = ns.SPAWN_MOBS and ns.SPAWN_MOBS[c]
      if m then
        lo = lo and math.min(lo, m[1]) or m[1]
        hi = hi and math.max(hi, m[2]) or m[2]
        elite = elite or (m[4] or 0) >= 1
        if not model and (m[3] or 0) > 0 then model, first = m[3], c end
      end
    end
  end
  return lo, hi, elite, model, first
end
ns.ObjectiveMobRange = MobRange -- (tests)

local function MobLevelText(lo, hi, elite)
  if not lo then return nil end
  local t = lo == hi and L["Level %d"]:format(lo) or L["Level %d-%d"]:format(lo, hi)
  if elite then t = t .. " " .. L["Elite"] end
  return t
end

-- "Kobold Vermin: 3/10" or "3/15 Defias Looter slain" -> have, need, the text without the count
local function Counts(text)
  text = tostring(text or "")
  local have, need = text:match("(%d+)%s*/%s*(%d+)")
  local name = text:gsub("^%s*%d+%s*/%s*%d+%s*", ""):gsub("%s*:?%s*%d+%s*/%s*%d+%s*$", "")
  name = name:match("^%s*(.-)%s*$")
  if name == "" then name = text end
  return tonumber(have), tonumber(need), name
end
ns.ObjectiveCounts = Counts -- (tests)

-- One objective as an entry. creatures: the ids seen for it here (may be empty).
local function ObjectiveEntry(questID, index, text, creatures)
  local o = ns.ATT_OBJECTIVES and ns.ATT_OBJECTIVES[questID]
  o = o and index and o[index]
  local items = type(o) == "table" and o[2]
  local item = type(items) == "table" and ns.Num(items[1]) or nil
  if (not creatures or #creatures == 0) and type(o) == "table" and type(o[1]) == "table" then creatures = o[1] end
  local have, need, name = Counts(text)
  local lo, hi, elite, model, first = MobRange(creatures)
  local pic
  if item then pic = { icon = C_Item and ns.Value(C_Item.GetItemIconByID, item) or ITEM_ICON }
  elseif first then pic = { model = model, creature = first, icon = MOB_ICON }
  else pic = { icon = OBJECT_ICON } end
  if (not text or text == "") then
    name = item and ns.ItemName(item) or (first and ns.LocalNpcName(first)) or "?"
  end
  local r, g, b = QuestColor(questID)
  return { entry = true, name = name, right = MobLevelText(lo, hi, elite), rightColor = hi and LevelRGB(hi) or nil, pic = pic,
    bar = need and { have or 0, need } or nil, barColor = { r, g, b } }
end

-- Objective dot tooltip: the quest in its level colour, the objective as an entry, what to use here.
function ns.ObjectivePinTooltip(pin)
  pin = pin or {}
  local lines = {}
  if pin.text or pin.creature then
    lines[#lines + 1] = ObjectiveEntry(pin.questID, pin.index, pin.text, pin.creature and { pin.creature } or nil)
  end
  if pin.needsItem then
    lines[#lines + 1] = { L[pin.dimmed and "Use %s here. First get it." or "Get %s here."]:format(ns.ItemName(pin.needsItem)) }
  end
  -- (1.2) no rewards here any more: the dot says what to do, the rewards are in the quest log
  return ns.LevelTitle(pin.questID), lines, L["Click: point the arrow here"]
end

-- (1.3.5) A bundled dot (minimap, world map): every objective it stands for once, by quest. (23.11.2026) no
-- "n objective spots" any more: the first quest is the card's title, further quests a heading in their colour.
function ns.ObjectiveBundleTooltip(pins)
  pins = pins or {}
  if #pins <= 1 then return ns.ObjectivePinTooltip(pins[1]) end
  local quests, byQuest = {}, {}
  for _, p in ipairs(pins) do
    local q = p.questID or 0
    local e = byQuest[q]
    if not e then e = { questID = q, objs = {}, order = {} } byQuest[q] = e quests[#quests + 1] = e end
    local key = tostring(p.index)
    local o = e.objs[key]
    if not o then o = { index = p.index, text = p.text, creatures = {}, seen = {} } e.objs[key] = o e.order[#e.order + 1] = o end
    local c = ns.Num(p.creature)
    if c and not o.seen[c] then o.seen[c] = true o.creatures[#o.creatures + 1] = c end
    if p.needsItem then o.needsItem, o.dimmed = p.needsItem, p.dimmed end
  end
  table.sort(quests, function(a, b) return a.questID < b.questID end)
  local lines = {}
  for qi, e in ipairs(quests) do
    if qi > 1 then lines[#lines + 1] = { header = Swatch(e.questID) .. ns.ColoredLevelTitle(e.questID) } end
    table.sort(e.order, function(a, b) return (tonumber(a.index) or 0) < (tonumber(b.index) or 0) end)
    for _, o in ipairs(e.order) do
      lines[#lines + 1] = ObjectiveEntry(e.questID, o.index, o.text, o.creatures)
      if o.needsItem then
        lines[#lines + 1] = { L[o.dimmed and "Use %s here. First get it." or "Get %s here."]:format(ns.ItemName(o.needsItem)) }
      end
    end
  end
  return ns.LevelTitle(quests[1].questID), lines, L["Click: point the arrow here"]
end

-- A quest to take ("!"): what it asks you to kill or collect, as entries without a bar (at most
-- MAX_GIVER_ENTRIES), from the objective data.
function ns.GiverObjectiveEntries(questID)
  local out = {}
  local objs = ns.ATT_OBJECTIVES and ns.ATT_OBJECTIVES[questID]
  if type(objs) ~= "table" then return out end
  local idx = {}
  for i in pairs(objs) do if type(i) == "number" then idx[#idx + 1] = i end end
  table.sort(idx)
  for _, i in ipairs(idx) do
    if #out >= MAX_GIVER_ENTRIES then break end
    local o = objs[i]
    local items = type(o) == "table" and o[2]
    local item = type(items) == "table" and ns.Num(items[1]) or nil
    local creatures = {}
    for _, c in ipairs(type(o) == "table" and type(o[1]) == "table" and o[1] or {}) do
      if ns.Num(c) then creatures[#creatures + 1] = ns.Num(c) end
    end
    local name = item and ns.ItemName(item) or (creatures[1] and ns.LocalNpcName(creatures[1]))
    if name and name ~= "" then
      local e = ObjectiveEntry(questID, i, nil, creatures)
      e.name, e.bar = name, nil
      out[#out + 1] = e
    end
  end
  return out
end

---------------------------------------------------------------------------
-- (1.3.5, Daniel 10.10., a quest field in Dun Morogh: "can be clustered more, or thinned, with that many")
-- Dense objective dots: a budget of markers. First the dots that lie on top of each other become one (the
-- round 5 rule, any quests). While more markers than the budget are left, the bundling distance grows by GROW
-- per step: up to SAME_STEPS steps only spots of the same quest join (the colour still tells the quest), then
-- MIX_STEPS more steps where any spots join. A bundle is the same dot a little larger (ns.BundleScale, at most
-- 1.3 times) at the middle of its spots; its tooltip names the quests and how many spots each has.
-- Points: { x, y (the same unit on both axes), q = quest, g = group (only the same group joins), f = how
-- willing it is to join (0.5-1; the minimap: near the player less), anchor = true: from the second step on it
-- joins nothing and takes only dots on top of it (the minimap: the nearest spot of each objective), pin }.
-- inView(point) says whether a marker counts for the budget (nil: all). Once per refresh or zoom step, never per
-- frame; a grid of cells, so 500 spots cost a few milliseconds at most. The same input gives the same output.
---------------------------------------------------------------------------
local GROW, SAME_STEPS, MIX_STEPS = 1.5, 8, 4
ns.THIN_GROW, ns.THIN_SAME_STEPS, ns.THIN_MIX_STEPS = GROW, SAME_STEPS, MIX_STEPS -- (tests)
local floor = math.floor

function ns.BundleScale(n)
  if n <= 1 then return 1 end
  if n <= 3 then return 1.1 end
  if n <= 6 then return 1.2 end
  return 1.3
end

-- The points live in reused arrays (ns.ThinBuffer), not in tables of their own: Daniel's minimap rebuilds a few
-- times a second while you walk, and fields added to its entries made every entry table larger. T.n points,
-- T.x, T.y, T.q, T.g, T.f (default 1), T.a (anchor) per point; T.order: the order they are taken in.
-- Out: T.head[i] = the point that draws point i, T.mx/T.my/T.cnt for heads.
local T = { n = 0, x = {}, y = {}, q = {}, g = {}, f = {}, a = {}, order = {}, head = {}, mx = {}, my = {}, sx = {}, sy = {}, cnt = {}, nxt = {} }
local grid, gridKeys = {}, {}
function ns.ThinBuffer(n)
  T.n = n
  local f, a, order = T.f, T.a, T.order
  for i = 1, n do f[i], a[i], order[i] = 1, false, i end
  for i = #order, n + 1, -1 do order[i] = nil end -- a longer list before: the order is sorted whole
  return T
end
local function Pass(base, level)
  local cell = base * GROW ^ level
  local mixed = level > SAME_STEPS
  local inv = 1 / cell
  local base2 = base * base
  local X, Y, Q, G, F, A, head, MX, MY, SX, SY, CNT, NXT = T.x, T.y, T.q, T.g, T.f, T.a, T.head, T.mx, T.my, T.sx, T.sy, T.cnt, T.nxt
  for i = 1, #gridKeys do grid[gridKeys[i]] = nil gridKeys[i] = nil end
  local order = T.order
  for k = 1, T.n do
    local i = order[k]
    local x, y = X[i], Y[i]
    head[i], MX[i], MY[i], SX[i], SY[i], CNT[i], NXT[i] = i, x, y, x, y, 1, false
    local cx, cy = floor(x * inv), floor(y * inv)
    local join
    if not (A[i] and level > 0) then -- an anchor joins nothing (it only takes dots on top of it)
      local r = level == 0 and cell or math.max(base, cell * F[i])
      local r2 = r * r
      local g, q = G[i], Q[i]
      for gx = cx - 1, cx + 1 do
        for gy = cy - 1, cy + 1 do
          local h = grid[gx * 1048576 + gy]
          while h and not join do
            if G[h] == g then
              local d2 = (MX[h] - x) ^ 2 + (MY[h] - y) ^ 2
              -- on top of each other: one; farther: same quest (later any quest), never into an anchor
              if d2 <= base2 or (level > 0 and d2 <= r2 and not A[h] and (mixed or Q[h] == q)) then join = h end
            end
            h = NXT[h]
          end
        end
      end
    end
    if join then
      head[i] = join
      local n = CNT[join] + 1
      CNT[join] = n
      SX[join], SY[join] = SX[join] + x, SY[join] + y
      MX[join], MY[join] = SX[join] / n, SY[join] / n
    else
      local key = cx * 1048576 + cy
      local first = grid[key]
      if not first then gridKeys[#gridKeys + 1] = key end
      NXT[i] = first or false
      grid[key] = i
    end
  end
end

-- (23.11.2026, Daniel: minimap pins that jump a few steps on) Pass joins a spot to the first head near it, so one
-- spot more or less at the edge of the list changes the bundles all along the chain. CellPass (the minimap, from
-- the first thinning step on): every spot of a fixed world cell (of the same quest up to SAME_STEPS) is one marker at
-- their middle, then markers on top of each other (closer than base) become one as in round 5. A marker only
-- changes when the spots of its own cell change. Without anchors and f (they counted from where you stand).
local cellOf, cellKeys = {}, {}
-- (24.11.2026, Ruckler) the world map's thinning may pause between its steps (ns.ThinWorldObjectives with pause): it
-- works in buffers of its own, and the minimap's (which may thin meanwhile) are put back for the pause
local function NewBuffers()
  return { { n = 0, x = {}, y = {}, q = {}, g = {}, f = {}, a = {}, order = {}, head = {}, mx = {}, my = {}, sx = {}, sy = {}, cnt = {}, nxt = {} },
    {}, {}, {}, {} }
end
local function SwapBuffers(set)
  local was = { T, grid, gridKeys, cellOf, cellKeys }
  T, grid, gridKeys, cellOf, cellKeys = set[1], set[2], set[3], set[4], set[5]
  return was
end
local function CellPass(base, level)
  local cell = base * GROW ^ level
  local mixed = level > SAME_STEPS
  local inv, binv, base2 = 1 / cell, 1 / base, base * base
  local X, Y, Q, G, head, MX, MY, SX, SY, CNT, NXT = T.x, T.y, T.q, T.g, T.head, T.mx, T.my, T.sx, T.sy, T.cnt, T.nxt
  for i = 1, #cellKeys do cellOf[cellKeys[i]] = nil cellKeys[i] = nil end
  for i = 1, #gridKeys do grid[gridKeys[i]] = nil gridKeys[i] = nil end
  local order, n = T.order, T.n
  for k = 1, n do
    local i = order[k]
    local x, y = X[i], Y[i]
    head[i], MX[i], MY[i], SX[i], SY[i], CNT[i], NXT[i] = i, x, y, x, y, 1, false
    -- a number per cell (and quest): cells of a few yards, world positions within +-20000 yards
    local key = (floor(x * inv) * 16384 + floor(y * inv)) * 262144 + (mixed and 0 or (tonumber(Q[i]) or 0) % 262144)
    local h = cellOf[key]
    if not h then
      cellOf[key] = i
      cellKeys[#cellKeys + 1] = key
    elseif G[h] == G[i] then
      head[i] = h
      local c = CNT[h] + 1
      CNT[h], SX[h], SY[h] = c, SX[h] + x, SY[h] + y
      MX[h], MY[h] = SX[h] / c, SY[h] / c
    end
  end
  for k = 1, n do
    local i = order[k]
    if head[i] == i then
      local x, y = MX[i], MY[i]
      local cx, cy = floor(x * binv), floor(y * binv)
      local join
      for gx = cx - 1, cx + 1 do
        for gy = cy - 1, cy + 1 do
          local h = grid[gx * 1048576 + gy]
          while h and not join do
            if G[h] == G[i] and (MX[h] - x) ^ 2 + (MY[h] - y) ^ 2 <= base2 then join = h end
            h = NXT[h]
          end
        end
      end
      if join then
        head[i] = join
        local c = CNT[join] + CNT[i]
        CNT[join], SX[join], SY[join] = c, SX[join] + SX[i], SY[join] + SY[i]
        MX[join], MY[join] = SX[join] / c, SY[join] / c
      else
        local key = cx * 1048576 + cy
        local first = grid[key]
        if not first then gridKeys[#gridKeys + 1] = key end
        NXT[i] = first or false
        grid[key] = i
      end
    end
  end
  for i = 1, n do local h = head[i] if head[h] ~= h then head[i] = head[h] end end -- members of a joined marker
end

-- Thins the points of the buffer (ns.ThinBuffer, filled by the caller). Returns the step used; T.head etc.
-- tell the result. budget nil: only the dots on top of each other. inView(T, i) says whether a head counts
-- for the budget (nil: all). prepare(T): called once before the first thinning step (order, anchors, f), so
-- a list within its budget costs one pass as in round 5.
-- (23.11.2026) keep: the step of the last thinning (the minimap); tried first with prepare called before, and kept
-- while the markers in view stay between KEEP_LOW and KEEP_HIGH times the budget (a step more or less for a few
-- markers made every bundle new).
local KEEP_LOW, KEEP_HIGH = 0.5, 1.5
ns.THIN_KEEP_LOW, ns.THIN_KEEP_HIGH = KEEP_LOW, KEEP_HIGH -- (tests)
local function Shown(inView)
  local shown, head = 0, T.head
  for i = 1, T.n do if head[i] == i and (not inView or inView(T, i)) then shown = shown + 1 end end
  return shown
end
-- cells: CellPass from the first step on (the minimap). pause: (24.11.2026) called before every step after the first
-- (the world map's thinning in slices; ns.ThinWorldObjectives swaps the buffers around it)
function ns.ThinObjectivePoints(base, budget, inView, prepare, keep, cells, pause)
  local step = cells and CellPass or Pass
  if budget and keep and keep > 0 and keep <= SAME_STEPS + MIX_STEPS then
    if prepare then prepare(T) end
    step(base, keep)
    local shown = Shown(inView)
    if shown <= budget * KEEP_HIGH and shown >= budget * KEEP_LOW then
      for i = 1, #gridKeys do grid[gridKeys[i]] = nil gridKeys[i] = nil end
      return keep
    end
    for i = 1, T.n do T.order[i] = i end -- as without keep: prepare sorts again
  end
  local level = 0
  while true do
    if level > 0 and pause then pause() end
    if level > 0 then step(base, level) else Pass(base, level) end
    if not budget then break end
    local shown = Shown(inView)
    if shown <= budget or level >= SAME_STEPS + MIX_STEPS then break end
    if level == 0 and prepare then
      if pause then pause() end -- (24.11.2026) the sort of the world map's spots is a step of its own
      prepare(T)
    end
    -- the first step over the budget jumps by a guess from the area of a cell (the square of its size), rounded
    -- down so it seldom goes too far (fewer passes for 500 spots)
    local jump = level == 0 and math.floor(0.5 * math.log(shown / budget) / math.log(GROW)) or 1
    level = math.min(SAME_STEPS + MIX_STEPS, level + math.max(1, jump))
  end
  for i = 1, #gridKeys do grid[gridKeys[i]] = nil gridKeys[i] = nil end
  for i = 1, #cellKeys do cellOf[cellKeys[i]] = nil cellKeys[i] = nil end
  return level
end

-- (1.3.5) World map: about WORLD_BUDGET objective markers on a zone map seen whole; zoomed in (the canvas scale,
-- in the half steps of ns.ClusterBucket) the budget grows with the area (bucket squared), so about as many are
-- on screen. Distances in canvas pixels of a zone map (1002 x 668, so y counts 1/1.5 of x).
local WORLD_BUDGET, CANVAS_W, CANVAS_ASPECT = 50, 1002, 1.5
ns.WORLD_OBJECTIVE_BUDGET = WORLD_BUDGET
local worldStats = { thinned = 0, level = 0, before = 0, after = 0 }
function ns.WorldThinStats() return worldStats end
-- pins: the display list of the world map; objective dots in it become fewer markers, everything else as it is.
local function ThinWorld(pins, bucket, dotSize, pause)
  worldStats.before, worldStats.after, worldStats.level, worldStats.thinned = 0, 0, 0, 0
  if ns.db.thinObjectives == false then return pins end
  bucket = bucket or 1
  local objs, out = {}, {}
  for _, p in ipairs(pins) do
    if p.kind == "objective" and tonumber(p.x) and tonumber(p.y) then objs[#objs + 1] = p else out[#out + 1] = p end
  end
  local n = #objs
  worldStats.before = n
  if n == 0 then return pins end
  local B = ns.ThinBuffer(n)
  for i, p in ipairs(objs) do B.x[i], B.y[i], B.q[i], B.g[i] = p.x, p.y / CANVAS_ASPECT, p.questID or 0, 0 end
  -- over the budget: quest by quest (then objective, place), so the same pins always give the same markers
  local function Prepare(T)
    table.sort(T.order, function(a, b)
      local pa, pb = objs[a], objs[b]
      if T.q[a] ~= T.q[b] then return T.q[a] < T.q[b] end
      local ia, ib = tonumber(pa.index) or 0, tonumber(pb.index) or 0
      if ia ~= ib then return ia < ib end
      if pa.x ~= pb.x then return pa.x < pb.x end
      if pa.y ~= pb.y then return pa.y < pb.y end
      return a < b
    end)
  end
  local base = 0.8 * (dotSize or 12) / (CANVAS_W * bucket)
  local level = ns.ThinObjectivePoints(base, WORLD_BUDGET * bucket * bucket, nil, Prepare, nil, nil, pause)
  local members = {}
  for i = 1, n do
    local h = B.head[i]
    if h ~= i then
      local m = members[h]
      if not m then m = { objs[h] } members[h] = m end
      m[#m + 1] = objs[i]
    end
  end
  local heads = 0
  for i = 1, n do
    if B.head[i] == i then
      heads = heads + 1
      local m = members[i]
      if m then
        -- the bundle's colour: the quest with the most spots in it (the first of them on a tie)
        local count, best = {}, nil
        local dimmed, small = true, true
        for _, mp in ipairs(m) do
          local q = mp.questID or 0
          count[q] = (count[q] or 0) + 1
          if not best or count[q] > count[best] then best = q end
          if not mp.dimmed then dimmed = false end
          if not mp.small then small = false end
        end
        local p = objs[i]
        -- (16.10. evening) the text is read when the tooltip shows (QuestData.lua, OBJECTIVE_PIN_META)
        out[#out + 1] = setmetatable({ kind = "objective", questID = best, index = p.index, x = B.mx[i], y = B.my[i] * CANVAS_ASPECT,
          members = m, scale = ns.BundleScale(#m), dimmed = dimmed or nil, small = small or nil, creature = p.creature }, ns.OBJECTIVE_PIN_META)
      else
        out[#out + 1] = objs[i]
      end
    end
  end
  worldStats.after, worldStats.level = heads, level
  worldStats.thinned = n - heads
  return out
end
-- pause: (24.11.2026) pause(part) between the thinning's steps (the map's refresh in slices), in buffers of its own;
-- the same markers as in one go. Never under a pcall (the pause yields).
local worldBuffers
function ns.ThinWorldObjectives(pins, bucket, dotSize, pause)
  if not pause then return ThinWorld(pins, bucket, dotSize) end
  worldBuffers = worldBuffers or NewBuffers()
  local saved = SwapBuffers(worldBuffers)
  local out = ThinWorld(pins, bucket, dotSize, function()
    SwapBuffers(saved)
    pause("thin")
    saved = SwapBuffers(worldBuffers)
  end)
  SwapBuffers(saved)
  return out
end

-- (17.10., Daniel: "do without our dots and merge clusters into one point; we wanted to draw an area") With the
-- symbols on, each objective's spots on the world map become groups: spots closer than CLUSTER_DIST (map widths,
-- smaller when zoomed in) to another spot of the group are one group. A group is one symbol (on the spot nearest
-- its middle, so it stands where a mob is) and, from AREA_MIN spots on, an area in the quest's colour under it
-- (QuestdonAreaPinMixin), like the game's own blue quest areas.
local CLUSTER_DIST, AREA_MIN = 0.045, 2
local SYMBOL_DIST = 0.04 -- (17.10.) symbols inside an area: about four symbol widths apart on the full map (0.022 was too many)
local symbolStats = { spots = 0, symbols = 0, areas = 0 }
function ns.SymbolStats() return symbolStats end
-- pins: the display list; returns the list with the objective spots replaced by symbols, and the areas
function ns.SymbolWorldObjectives(pins, bucket)
  bucket = bucket or 1
  local out, groups, order = {}, {}, {}
  for _, p in ipairs(pins) do
    if p.kind == "objective" and tonumber(p.x) and tonumber(p.y) then
      -- (17.10., Daniel: "the world still looks overloaded") one group per quest and symbol: two kinds of trogg of one
      -- quest are one area with swords, not two lying on top of each other
      local key = tostring(p.questID) .. ":" .. tostring(ns.PinIconKind(p) or p.index) .. ":" .. tostring(p.useItem)
      local g = groups[key]
      if not g then g = {} groups[key] = g order[#order + 1] = key end
      g[#g + 1] = p
    else
      out[#out + 1] = p
    end
  end
  local areas = {}
  local d = CLUSTER_DIST / bucket
  local d2 = d * d
  symbolStats.spots, symbolStats.symbols, symbolStats.areas = 0, 0, 0
  for _, key in ipairs(order) do
    local g = groups[key]
    local n = #g
    symbolStats.spots = symbolStats.spots + n
    -- single linkage over a grid of d: spots in neighbouring cells are compared
    local parent, cells = {}, {}
    local function Find(i) while parent[i] ~= i do parent[i] = parent[parent[i]] i = parent[i] end return i end
    for i = 1, n do
      parent[i] = i
      local p = g[i]
      local cx, cy = math.floor(p.x / d), math.floor(p.y / CANVAS_ASPECT / d)
      for ox = -1, 1 do
        for oy = -1, 1 do
          local list = cells[(cx + ox) * 4096 + cy + oy]
          -- (25.10., bench "map zoom": `list or {}` made an empty table per neighbour cell, 9 per spot and zoom step)
          if list then
            for _, j in ipairs(list) do
              local q = g[j]
              if (p.x - q.x) ^ 2 + ((p.y - q.y) / CANVAS_ASPECT) ^ 2 <= d2 then
                local a, b = Find(i), Find(j)
                if a ~= b then parent[a] = b end
              end
            end
          end
        end
      end
      local k = cx * 4096 + cy
      local list = cells[k]
      if not list then list = {} cells[k] = list end
      list[#list + 1] = i
    end
    local members, heads = {}, {}
    for i = 1, n do
      local r = Find(i)
      local m = members[r]
      if not m then m = {} members[r] = m heads[#heads + 1] = r end
      m[#m + 1] = g[i]
    end
    for _, r in ipairs(heads) do
      local m = members[r]
      symbolStats.symbols = symbolStats.symbols + 1
      if #m == 1 then
        out[#out + 1] = m[1]
      else
        local sx, sy, dimmed = 0, 0, true
        for _, p in ipairs(m) do sx, sy = sx + p.x, sy + p.y if not p.dimmed then dimmed = false end end
        sx, sy = sx / #m, sy / #m
        -- (17.10., Daniel: "more swords on the world map") inside the area several symbols: from the middle out, a
        -- spot gets its own symbol when no symbol stands within SYMBOL_DIST; the others join the nearest one
        local sorted = {}
        for i, p in ipairs(m) do sorted[i] = p end
        local function D2(p, q) return (p.x - q.x) ^ 2 + ((p.y - q.y) / CANVAS_ASPECT) ^ 2 end
        local mid = { x = sx, y = sy }
        table.sort(sorted, function(p, q) return D2(p, mid) < D2(q, mid) end)
        local sd2 = (SYMBOL_DIST / bucket) ^ 2
        local heads2, own = {}, {}
        for _, p in ipairs(sorted) do
          local near, nearD
          for _, h in ipairs(heads2) do
            local dd = D2(p, h)
            if not nearD or dd < nearD then near, nearD = h, dd end
          end
          if near and nearD < sd2 then local l = own[near] l[#l + 1] = p
          else heads2[#heads2 + 1] = p own[p] = { p } end
        end
        for _, h in ipairs(heads2) do
          local l = own[h]
          if #l == 1 then out[#out + 1] = h
          else
            out[#out + 1] = setmetatable({ kind = "objective", questID = h.questID, index = h.index, x = h.x, y = h.y,
              members = l, creature = h.creature, useItem = h.useItem, needsItem = h.needsItem, dimmed = dimmed or nil },
              ns.OBJECTIVE_PIN_META)
          end
        end
        symbolStats.symbols = symbolStats.symbols + #heads2 - 1
        local best = sorted[1]
        if #m >= AREA_MIN and ns.db.objectiveAreas ~= false then
          areas[#areas + 1] = { kind = "area", questID = best.questID, points = m, dimmed = dimmed or nil }
          symbolStats.areas = symbolStats.areas + 1
        end
      end
    end
  end
  return out, areas
end
function ns.SymbolsOn() return ns.db.objectiveIcons ~= false end

-- (1.17) Signature of a pin set: refreshes from events skip the rebuild when
-- nothing visible changed (same map, same pins, same texts).
local lastSig, precomputed
local sameNow -- (24.11.2026) a request of our own that wants the pins worked out at once (ns.RefreshPins)
-- (25.10., OFFEN "Karte zoomen (39 KB/s)": Daniel's /qd mem with the map open and zoomed, "map inner" 35 KB/s, about 110 KB per
-- zoom step) the display list of each zoom step, kept while the pins stay the same (same map, same signature, same options):
-- zooming back to a step seen before draws it from here instead of grouping all spots again. At most ZOOM_KEEP steps.
local zoomCache, zoomCacheSig, zoomCacheN = {}, nil, 0
-- (07.11.2026, Daniel: "auch bei der Weltkarte, werden die Flächen nach abschalten der funktion nicht ausgeblendet") the
-- display options of the last build: a changed option (areas, symbols, sizes) builds anew, even with the same pins
local lastZKey
local ZOOM_KEEP = 4
local function ZoomKey(objB)
  return ("%s|%s|%s|%s|%s|%s"):format(objB, ns.SymbolsOn() and 1 or 0, tostring(ns.db.thinObjectives),
    tostring(ns.db.objectivePinSize), tostring(ns.db.objectiveAreas), tostring(ns.db.skipGameGivers))
end
function ns.MapZoomCacheSize() return zoomCacheN end
local objBucket, objThinned = 1, false -- (1.3.5) zoom step of the objective thinning; true: another zoom can change the dots
local stats = { builds = 0, skipped = 0 }
local function PinKey(p)
  -- (16.10. evening, /qd mem) a quest mob's dot is the same table while nothing on it changed (QuestData.lua):
  -- its key is made once
  if p.kind == "objective" and p._key then return p._key end
  local extra = ""
  if p.kind == "entrance" or p.kind == "dungeon" or p.kind == "way" then
    extra = tostring(p.name) .. tostring(p.inst)
  elseif p.kind ~= "objective" then
    extra = ns.QuestTitle(p.questID)
    if p.kind == "turnin" and ns.QuestRewardLines then extra = extra .. table.concat(ns.QuestRewardLines(p.questID) or {}, ",") end
    if p.kind ~= "turnin" and ns.PartyMemberCount and ns.PartyMemberCount() > 0 then
      extra = extra .. "|" .. table.concat(ns.PartyMembersWithQuest(p.questID), ",")
    end
  end
  -- (1.23) one string per pin (was a table of 13 strings)
  local key = ("%s:%s:%s:%.4f:%.4f:%s:%s:%s:%s:%s:%s:%s:%s"):format(tostring(p.kind), tostring(p.questID), tostring(p.index or ""),
    tonumber(p.x) or 0, tonumber(p.y) or 0, (p.dimmed and "d" or "") .. (p.small and "s" or ""), p.learned and "l" or "",
    (p.confirmed and "c" or "") .. (p.gameShown and "g" or ""), -- (1.24, 1.25)
    tostring(p.npc or ""), tostring(p.kind ~= "objective" and p.text or "") .. tostring(p.statusText or "") .. tostring(p.iconKind or ""), tostring(p.needsItem or ""), tostring(p.creature or ""), extra)
  if p.kind == "objective" then p._key = key end
  return key
end
-- (16.10. evening, /qd mem) The signature was all keys sorted and joined: a string of up to 30 KB for every
-- build of the map and the minimap. Now each distinct key gets two random numbers once, and the signature is the
-- count and two sums of them (the order of the pins does not matter, as before with the sorted keys).
local keyA, keyB, keyCount = {}, {}, 0
local SIG_M = 2147483647
-- pause: (24.11.2026, Ruckler) the map's refresh in slices pauses every 32 pins (a key is a long string.format)
local function Signature(mapID, pins, pause)
  local s1, s2 = 0, 0
  for i, p in ipairs(pins) do
    if pause and i % 32 == 0 then pause("signature") end
    local k = PinKey(p)
    local a = keyA[k]
    if not a then
      if keyCount >= 20000 then keyA, keyB, keyCount = {}, {}, 0 end
      a = math.random(1, 67108864)
      keyA[k], keyB[k] = a, math.random(1, 67108864)
      keyCount = keyCount + 1
    end
    s1 = (s1 + a) % SIG_M
    s2 = (s2 + (a * keyB[k]) % SIG_M) % SIG_M
  end
  return ("%s|%s|%d|%d|%d"):format(tostring(mapID), tostring(ns.db.objectivePinSize or 12), #pins, s1, s2)
end
-- (1.23) The world map and the minimap of the same zone compare the same pin
-- list (ns.PinsForMap, once per scope) in the batched refresh: the signature
-- of that list is worked out once. Pin lists are never changed after they
-- are built; every refresh builds a new one.
local sigPins, sigMap, sigValue
function ns.PinsSignature(mapID, pins, pause)
  if pins ~= sigPins or mapID ~= sigMap then
    local v = Signature(mapID, pins, pause)
    sigPins, sigMap, sigValue = pins, mapID, v
  end
  return sigValue
end
function ns.MapPinStats() return stats end

local setupFailed = false
-- (DonMap M3b, 30.10.2026) the map's data provider is DonMap's (DonMapAPI.NewWorldProvider): it keeps the rules for
-- combat (the pins of the map last drawn stay), the closed map, the build right before combat and "all our pins still on
-- the canvas"; what is drawn stays here (build, same, zoomed below)
-- (23.10., Daniel's /qd mem with Leveldon: "map" 69 KB a second at 0.7 calls, also with the map closed) who asks the
-- map to draw: while /qd mem runs, each call is counted as "map from <file:line>" (the first place outside Questdon)
local function MapCaller(closed)
  if not (ns.MemProfiling and ns.MemProfiling() and debugstack) then return end
  local ok, stack = pcall(debugstack, 2, 12, 0)
  local at = "?"
  if ok and type(stack) == "string" then
    for w in stack:gsub("\\", "/"):gmatch("([%w_]+%.lua:%d+)") do
      if not (w:find("^Core%.lua:") or w:find("^MapPins%.lua:")) then at = w break end
    end
  end
  ns.MemCount("map from " .. at .. (closed and " (closed)" or ""))
end
-- (Daniel 26.10.: "dass jeder die selber skalieren kann") one factor for all our world map pins, 25 to 200 %
function ns.MapPinMult()
  local v = tonumber(ns.db and ns.db.mapPinScale) or 1 -- (12.11.2026, Daniel) 100 % by default
  return math.max(0.25, math.min(2, v))
end
-- the map's own scaling first (from 1, so the factor never adds up), then ours on top
-- (12.11.2026, Daniel's picture at 100 %: "die ? und ausrufezeichen im verhältnis zu den pins zu groß") the game's ! and ?
-- art is about a third bigger than our objective symbols: quest givers and turn-ins are drawn at 70 % of it
ns.QUEST_MARK_FACTOR = 0.7
local function ScaleBy(self, base)
  if not self.SetScale then return end
  self:SetScale(1)
  if base then base(self) end
  local s = self.GetScale and self:GetScale() or 1
  local m = ns.MapPinMult()
  local k = type(self.qdPin) == "table" and self.qdPin.kind
  local mark = k == "available" or k == "turnin"
  if mark then m = m * ns.QUEST_MARK_FACTOR end
  self.qdMarkScaled = mark -- (15.11.2026) what this frame was last sized for (QuestPin:OnAcquired)
  self:SetScale((tonumber(s) or 1) * m)
  -- (02.11.2026, Daniel's video: with the pin size at 75 % all pins jumped to the top left once the map rescaled them)
  -- the map places a pin for its scale (the offset divided by it); with ours on top it is placed again for the final one
  if m ~= 1 and self.ApplyCurrentPosition and self.GetMap and self:GetMap()
     and (self.normalizedX or (self.GetPosition and self:GetPosition())) then
    self:ApplyCurrentPosition()
  end
end
local Setup
function Setup()
  if provider or setupFailed then return end
  if not (WorldMapFrame and WorldMapFrame.AddDataProvider and BaseMapPoiPinMixin
          and BaseMapPoiPinMixin.CreateSubPin and MapCanvasDataProviderMixin and MapCanvasPinMixin) then return end

  -- Quest start / turn-in: Blizzard's POI pin look ("!" and "?").
  QuestdonQuestPinMixin = BaseMapPoiPinMixin:CreateSubPin("PIN_FRAME_LEVEL_AREA_POI")
  local QuestPin = QuestdonQuestPinMixin
  -- (1.3.5, Daniel 10.10.) "Show on map": the entrance's pin pulses for a few seconds (our own glow
  -- texture on our own pin; pooled pins hide it again for anything else)
  local function ApplyHighlight(self, pin)
    local on = pin and (pin.kind == "dungeon" or pin.kind == "entrance") and ns.EntranceHighlighted and ns.EntranceHighlighted(pin.inst, pin.insts)
    -- (24.11.2026, Daniel with An Unsettling Discovery: three "?" side by side at Farrholde Keep, which one is mine?) the
    -- "!" or "?" the arrow leads to glows the same way, as long as it is the target
    if not on and pin and ns.IsArrowTargetPin(pin) then on = true end
    if on and not self.qdGlow and self.CreateTexture then
      local g = self:CreateTexture(nil, "BACKGROUND")
      g:SetPoint("CENTER", self, "CENTER", 0, 0)
      g:SetSize(52, 52)
      g:SetTexture("Interface\\AddOns\\Questdon\\Media\\ArrowSealGlow")
      if g.SetBlendMode then pcall(g.SetBlendMode, g, "ADD") end
      g:SetVertexColor(1, 0.85, 0.5)
      if g.CreateAnimationGroup then
        local ok, group = pcall(g.CreateAnimationGroup, g)
        if ok and group then
          group:SetLooping("BOUNCE")
          local fade = group:CreateAnimation("Alpha")
          if fade then fade:SetFromAlpha(0.25) fade:SetToAlpha(1) fade:SetDuration(0.6) end
          self.qdPulse = group
        end
      end
      self.qdGlow = g
    end
    if self.qdGlow then
      if on then self.qdGlow:Show() if self.qdPulse then self.qdPulse:Play() end
      else self.qdGlow:Hide() if self.qdPulse then self.qdPulse:Stop() end end
    end
    self.qdHighlighted = on and true or false
  end
  -- (11.11.2026, Daniel: "Pin mit der Spitze auf die Koordinate") the picture of a waypoint stands on its spot: the
  -- texture sits above the middle of the pin; a pin used again for something else gets its picture back in the middle
  local function WayAnchor(self, on)
    if not on and not self.qdWayAnchor then return end
    for _, tex in ipairs({ self.Texture, self.HighlightTexture }) do
      if type(tex) == "table" and tex.ClearAllPoints and tex.SetPoint then
        pcall(tex.ClearAllPoints, tex)
        if on then pcall(tex.SetPoint, tex, "BOTTOM", self, "CENTER", 0, 0) else pcall(tex.SetPoint, tex, "CENTER", self, "CENTER", 0, 0) end
      end
    end
    self.qdWayAnchor = on or nil
  end
  -- (24.11.2026) the arrow's target changes without a rebuild of the pins (a click, the next quest): the shown "!" and
  -- "?" look again twice a second while the map is open, only when the target changed
  local lastArrowKey
  ns.NewTicker(0.5, function()
    if not (WorldMapFrame and WorldMapFrame:IsShown() and provider) then lastArrowKey = nil return end
    local key = ns.ArrowTargetPinKey()
    if key == lastArrowKey then return end
    lastArrowKey = key
    local map = provider.GetMap and provider:GetMap()
    if not (map and map.EnumeratePinsByTemplate) then return end
    local ok, iter, state, start = pcall(map.EnumeratePinsByTemplate, map, QUEST_TEMPLATE)
    if not ok or type(iter) ~= "function" then return end
    for p in iter, state, start do
      if type(p) == "table" and type(p.qdPin) == "table" then ApplyHighlight(p, p.qdPin) end
    end
  end)
  local Acquire
  -- (12.11.2026) the size depends on what the pin shows: set again once that is known (a pooled pin showed something else)
  function QuestPin:OnAcquired(pin)
    self.qdPin = nil
    -- (19.11.2026) raised above the game's "!" for a turn-in (ns.RaiseTurnInPins): back to its own level
    if self.qdLevelWas then
      if self.SetFrameLevel then pcall(self.SetFrameLevel, self, self.qdLevelWas) end
      self.qdLevelWas = nil
    end
    Acquire(self, pin)
    -- (15.11.2026, CurseForge Neidhardt: "when I open my map, there's a micro-freeze") only when the frame was last sized
    -- for the other kind (! and ? against the rest): before, every pin was sized and placed a second time on every rebuild
    local k = type(pin) == "table" and pin.kind
    if self.qdMarkScaled ~= (k == "available" or k == "turnin") and self.ApplyCurrentScale and self.GetMap and self:GetMap() then
      pcall(self.ApplyCurrentScale, self)
    end
  end
  function Acquire(self, pin)
    WayAnchor(self, false)
    ApplyHighlight(self, pin)
    -- (1.3.5) a marked dungeon entrance: the game's dungeon entrance icon
    if pin.kind == "entrance" then
      local name = L["Entrance: %s"]:format(pin.name or "?")
      BaseMapPoiPinMixin.OnAcquired(self, { name = name, atlasName = "Dungeon", position = CreateVector2D(pin.x, pin.y) })
      self.qdName, self.qdDesc, self.qdPin = name, L["Click: dungeon journal, right-click: remove the mark"], pin
      if self.SetAlpha then pcall(self.SetAlpha, self, 1) end
      return
    end
    -- (10.11.2026) the waypoint of /way: our "place" symbol; a right-click removes it
    if pin.kind == "way" then
      BaseMapPoiPinMixin.OnAcquired(self, { name = pin.name or "?", atlasName = "QuestNormal", position = CreateVector2D(pin.x, pin.y) })
      local size = math.floor(ns.WAY_PIN_SIZE * ns.WayPinScale() + 0.5)
      for _, tex in ipairs({ self.Texture, self.HighlightTexture }) do
        if type(tex) == "table" and tex.SetTexture then
          pcall(tex.SetTexture, tex, ns.WAY_ICON)
          if tex.SetSize then pcall(tex.SetSize, tex, size, size) end -- (11.11.2026) smaller, and the size the player set
        end
      end
      if self.SetSize then pcall(self.SetSize, self, size, size * 2) end -- the mouse finds the whole picture
      WayAnchor(self, true)
      self.qdName, self.qdDesc, self.qdPin = pin.name or "?", L["Click: arrow, right-click: remove waypoints"], pin
      if self.SetAlpha then pcall(self.SetAlpha, self, 1) end
      return
    end
    -- (1.3.5) the entrance of a dungeon (always there): the same icon, a little quieter than the mark
    if pin.kind == "dungeon" then
      BaseMapPoiPinMixin.OnAcquired(self, { name = pin.name or "?", atlasName = "Dungeon", position = CreateVector2D(pin.x, pin.y) })
      self.qdName, self.qdDesc, self.qdPin = pin.name or "?", L["Click: dungeon journal, right-click: arrow"], pin
      if self.SetAlpha then pcall(self.SetAlpha, self, 0.8) end
      return
    end
    local title = ns.QuestTitle(pin.questID)
    -- (1.22) "[?]" for a quest without a known level (never guessed)
    -- (1.26) the level in its difficulty colour, as in the panel and the tooltips
    title = ns.QuestLevelTag(pin.questID) .. title
    -- (1.21) quest giver with several quests: one pin
    if pin.group and #pin.group > 1 then title = title .. " " .. L["(+%d more)"]:format(#pin.group - 1) end
    -- (1.20) the description (rewards, chain, group, giver) is built only
    -- when something asks for it: our own tooltip does not use it
    BaseMapPoiPinMixin.OnAcquired(self, {
      name = title,
      atlasName = (pin.kind == "turnin" or pin.iconKind == "turnin") and "QuestTurnin" or "QuestNormal",
      position = CreateVector2D(pin.x, pin.y),
    })
    self.qdName, self.qdDesc, self.qdPin = title, nil, pin
    if self.SetAlpha then pcall(self.SetAlpha, self, pin.dimmed and 0.5 or 1) end
  end
  function QuestPin:ApplyCurrentScale() ScaleBy(self, BaseMapPoiPinMixin.ApplyCurrentScale or MapCanvasPinMixin.ApplyCurrentScale) end
  -- Left click: point the arrow there.
  function QuestPin:OnMouseClickAction(button)
    -- (1.3.5) a dungeon entrance: a click opens the dungeon journal, right-click marks it (or removes the mark)
    if self.qdPin and self.qdPin.kind == "dungeon" then
      if button == "RightButton" then ns.DungeonPinRightClick(self.qdPin.inst)
      elseif button == "LeftButton" then ns.OpenDungeonJournal(self.qdPin.inst) end
      return
    end
    -- (round 8) the mark's pin: a click opens the dungeon journal too (the arrow already points there)
    if self.qdPin and self.qdPin.kind == "entrance" then
      if button == "RightButton" then ns.RemoveEntranceMark("pin")
      elseif button == "LeftButton" then ns.OpenDungeonJournal(self.qdPin.inst) end
      return
    end
    -- (10.11.2026) a waypoint of /way: a right-click removes it, a click points the arrow at it
    if self.qdPin and self.qdPin.kind == "way" then
      if button == "RightButton" then ns.WayMenu(self.qdPin.way)
      elseif button == "LeftButton" then ns.PickWay(self.qdPin.way) end
      return
    end
    -- (1.1) Alt-click: "no quest here" (NotHere.lua)
    if button == "LeftButton" and self.qdPin and self.qdPin.kind ~= "focus" and ns.True(ns.Value(IsAltKeyDown)) and ns.ReportPin then
      ns.ReportPin(self.qdPin)
      return
    end
    if button == "LeftButton" and self.qdPin then
      local label = self.qdPin.group and ns.QuestGroupTitle(self.qdPin) or ns.QuestTitle(self.qdPin.questID)
      local q = self.qdPin
      -- (19.11.2026) a "?" on the continent map: the arrow goes to its point on the zone map
      if q.zoneMap and q.zx then ns.PointArrowFromPin(q.zoneMap, q.zx, q.zy, label, nil, q)
      else ns.PointArrowFromPin(ns.Num(self:GetMap():GetMapID()), q.x, q.y, label, nil, q) end
    end
  end
  -- (1.3.5, Daniel 10.10.: "right-click on a dungeon entrance zooms out of the map") The map canvas lets
  -- right-clicks of every pin pass through to the map (zoom out) unless the pin says otherwise; it asks
  -- after OnAcquired. Entrance pins keep their right-click (the arrow mark); quest pins zoom out as before.
  function QuestPin:ShouldMouseButtonBePassthrough(button)
    local kind = self.qdPin and self.qdPin.kind
    if button == "RightButton" and (kind == "dungeon" or kind == "entrance" or kind == "way") then return false end
    return button == "RightButton"
  end
  -- (1.2) map canvases that call OnClick instead of OnMouseClickAction
  QuestPin.OnClick = ns.Guard("map click", function(self, button) self:OnMouseClickAction(button) end)
  function QuestPin.UseTooltip() return true end
  function QuestPin:GetBestNameAndDescription()
    if self.qdDesc == nil and self.qdPin then self.qdDesc = ns.QuestPinDescription(self.qdPin) end
    return self.qdName, self.qdDesc
  end
  -- (1.19) own tooltip in the family structure (our mixin, our pins only)
  QuestPin.OnMouseEnter = ns.Guard("map tooltip", function(self)
    if not self.qdPin then return end
    local tip = self.qdPin.kind == "entrance" and ns.EntrancePinTooltip or self.qdPin.kind == "dungeon" and ns.DungeonPinTooltip
      or self.qdPin.kind == "way" and ns.WayPinTooltip
      or self.qdPin.group and ns.QuestGroupTooltip or ns.QuestPinTooltip
    local title, lines, hint = tip(self.qdPin)
    -- (1.3.6) our own hover card (PinCard.lua)
    ns.PinCard(self, title, lines, hint, ns.PinCardKind(self.qdPin.group and self.qdPin.group[1] or self.qdPin))
    ns.SetHoverTooltip(self, self.OnMouseEnter) -- (1.3.4) Shift redraws it
  end)
  function QuestPin:OnMouseLeave() ns.PinCardHide(self) ns.SetHoverTooltip(nil) end

  -- Objective spawns: small coloured dots.
  local SQUARE, DOT, QUARTER = "Interface\\Buttons\\WHITE8X8", "Interface\\COMMON\\Indicator-Yellow", math.pi / 4
  local SYMBOLS = "Interface\\AddOns\\Questdon\\Media\\"
  local function Turn(tex, angle) if tex and tex.SetRotation then pcall(tex.SetRotation, tex, angle) end end
  QuestdonObjectivePinMixin = CreateFromMixins(MapCanvasPinMixin)
  local ObjPin = QuestdonObjectivePinMixin
  function ObjPin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
    if self.SetScalingLimits then self:SetScalingLimits(1, 0.9, 1.4) end
  end
  function ObjPin:ApplyCurrentScale() ScaleBy(self, MapCanvasPinMixin.ApplyCurrentScale) end
  function ObjPin:OnAcquired(pin)
    self.pin = pin
    local size = ns.db.objectivePinSize or 12
    if pin.small then size = math.max(6, math.floor(size * 0.7 + 0.5)) end -- (1.2) many spawns: smaller dots
    if pin.scale then size = math.min(math.floor(size * pin.scale + 0.5), math.floor(size * 1.3)) end -- (1.3.5) a bundle, at most 1.3 times
    -- (1.3.8, F2) objects to click: a diamond with a dark edge, mobs keep the round dot; (F9) the place of use of a
    -- quest item: the item's icon in a frame of the quest's colour
    local item = ns.PinUseItem(pin)
    local icon = item and C_Item and ns.Value(C_Item.GetItemIconByID, item) or nil
    -- (17.10.) single targets get their own symbol (named mob, object, place, item not yet known) in a halo of the
    -- quest's colour
    local sym = not icon and ns.PinIconKind(pin)
    if sym then icon = SYMBOLS .. ns.PIN_ICONS[sym] end
    local shape = sym and "symbol" or icon and "item" or ns.IsObjectPin(pin) and "diamond" or nil
    if shape == "item" then size = math.floor(size * 1.35 + 0.5)
    elseif shape == "symbol" then size = math.floor(size * 1.6 + 0.5)
    elseif shape == "diamond" then size = math.max(5, math.floor(size * 0.75 + 0.5)) end
    self:SetSize(size, size)
    self:SetPosition(pin.x, pin.y)
    local dot = self.Dot
    if dot and dot.SetTexture and (shape or self.shape) then
      dot:SetTexture(icon or (shape == "diamond" and SQUARE) or DOT)
      Turn(dot, shape == "diamond" and QUARTER or 0)
      if dot.SetTexCoord then
        local a, b = shape == "item" and 0.08 or 0, shape == "item" and 0.92 or 1
        dot:SetTexCoord(a, b, a, b)
      end
    end
    if shape and not self.Edge and self.CreateTexture then
      local e = self:CreateTexture(nil, "ARTWORK")
      e:SetPoint("CENTER", self, "CENTER", 0, 0)
      e:SetTexture(SQUARE)
      self.Edge = e
    end
    -- (20.10.) a symbol's bronze rim takes the quest's colour (one shared grey ring over the painted symbol)
    if shape == "symbol" and self.CreateTexture then
      if not self.Rim then
        local rim = self:CreateTexture(nil, "OVERLAY", nil, 1)
        rim:SetPoint("CENTER", self, "CENTER", 0, 0)
        rim:SetTexture(SYMBOLS .. "qd_rim")
        self.Rim = rim
      end
      self.Rim:SetSize(size, size)
      self.Rim:SetVertexColor(QuestColor(pin.questID))
      self.Rim:Show()
    elseif self.Rim then
      self.Rim:Hide()
    end
    if self.Edge then
      if shape == "symbol" then
        self.Edge:Hide()
      elseif shape then
        self.Edge:SetTexture(SQUARE)
        Turn(self.Edge, shape == "diamond" and QUARTER or 0)
        local pad = (shape == "item" or shape == "symbol") and 4 or 3
        self.Edge:SetSize(size + pad, size + pad)
        if shape == "item" or shape == "symbol" then self.Edge:SetVertexColor(QuestColor(pin.questID))
        else self.Edge:SetVertexColor(0, 0, 0, 0.85) end
        self.Edge:Show()
      else
        self.Edge:Hide()
      end
    end
    self.shape = shape
    if dot then
      if icon then dot:SetVertexColor(1, 1, 1) else dot:SetVertexColor(QuestColor(pin.questID)) end
    end
    -- place of use of an item not yet in the bags: dimmed
    if self.SetAlpha then self:SetAlpha(pin.dimmed and 0.35 or 1) end
  end
  -- (1.3.8, F8) while the mouse is on a quest's dot the other quests' dots step back
  local function HoverWorldSet(set, map)
    if not (map and map.EnumeratePinsByTemplate) then return end
    local ok, iter, state, start = pcall(map.EnumeratePinsByTemplate, map, OBJECTIVE_TEMPLATE)
    if not ok or type(iter) ~= "function" then return end
    for p in iter, state, start do
      if type(p) == "table" and p.pin and p.SetAlpha then
        local base = p.pin.dimmed and 0.35 or 1
        local mine = not set
        for _, m in ipairs(set and (p.pin.members or { p.pin }) or {}) do if set[m.questID] then mine = true break end end
        p:SetAlpha(mine and base or base * 0.3)
      end
    end
  end
  local function HoverWorldDots(self, on)
    local map = self.GetMap and self:GetMap()
    local set
    if on and self.pin then
      set = {}
      for _, m in ipairs(self.pin.members or { self.pin }) do if m.questID then set[m.questID] = true end end
    end
    HoverWorldSet(set, map)
  end
  -- (20.10., Daniel) the mouse on a quest's row in the list: its marks on the world map and the minimap stay, the
  -- others step back. The row has no leave callback we may use, so a small frame watches the mouse until it is gone.
  local rowWatch, rowHover
  function ns.HoverQuestRow(row, questID)
    if not (row and questID) then return end
    local set = { [questID] = true }
    rowHover = row
    if WorldMapFrame and WorldMapFrame.IsShown and WorldMapFrame:IsShown() then HoverWorldSet(set, WorldMapFrame) end
    if ns.MinimapHoverQuests then ns.MinimapHoverQuests(set) end
    if not rowWatch and CreateFrame then
      rowWatch = CreateFrame("Frame")
      rowWatch:SetScript("OnUpdate", function(self)
        local row = rowHover
        local over = row and row.IsMouseOver and row:IsShown() and row:IsMouseOver()
        if over then return end
        rowHover = nil
        self:Hide()
        if WorldMapFrame and WorldMapFrame.IsShown and WorldMapFrame:IsShown() then HoverWorldSet(nil, WorldMapFrame) end
        if ns.MinimapHoverQuests then ns.MinimapHoverQuests(nil) end
      end)
    end
    if rowWatch then rowWatch:Show() end
  end
  ns.HoverWorldDots = HoverWorldDots -- (tests)
  ObjPin.OnMouseEnter = ns.Guard("map tooltip", function(self)
    if not self.pin then return end
    HoverWorldDots(self, true)
    local title, lines, hint
    if self.pin.members then title, lines, hint = ns.ObjectiveBundleTooltip(self.pin.members) -- (1.3.5) a bundle
    else title, lines, hint = ns.ObjectivePinTooltip(self.pin) end
    local first = self.pin.members and self.pin.members[1] or self.pin
    ns.PinCard(self, title, lines, hint, ns.PinCardKind(nil, first.questID))
  end)
  function ObjPin:OnMouseLeave() ns.PinCardHide(self) HoverWorldDots(self, false) end
  function ObjPin:OnMouseClickAction(button)
    if button == "LeftButton" and self.pin then
      ns.PointArrowFromPin(ns.Num(self:GetMap():GetMapID()), self.pin.x, self.pin.y, ns.QuestTitle(self.pin.questID), "objective",
        self.pin.members and self.pin.members[1] or self.pin)
    end
  end
  ObjPin.OnClick = ns.Guard("map click", function(self, button) self:OnMouseClickAction(button) end)

  -- (17.10.) The area of a group of spots: soft round blobs (AREA_RADIUS map widths) on its spots,
  -- drawn row by row as strips in the quest's colour (no strip on top of another, so the colour is even). The
  -- frame lies on the map's canvas and grows with the zoom like the map itself.
  local AREA_RADIUS, AREA_ALPHA, AREA_STEP = 0.02, 0.2, 0.75
  local BLOB = "Interface\\AddOns\\Questdon\\Media\\qd_blob"
  QuestdonAreaPinMixin = CreateFromMixins(MapCanvasPinMixin)
  local AreaPin = QuestdonAreaPinMixin
  function AreaPin:OnLoad()
    -- (17.10., Daniel: "no areas in different colours") at the exploration level the explored map art (opaque
    -- tiles at the same level) covered the areas: the level of the game's own quest areas, else the area POIs'
    pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_AREA_POI")
    self.qdLevel = "PIN_FRAME_LEVEL_AREA_POI"
    if self.EnableMouse then self:EnableMouse(false) end
  end
  function AreaPin:ApplyCurrentScale() if self.SetScale then self:SetScale(1) end end
  function AreaPin:OnAcquired(area)
    self.area = area
    local map = self.GetMap and self:GetMap()
    -- the level the map knows: the game's quest areas', else the event overlays' (above the explored map art)
    local mgr = map and map.GetPinFrameLevelsManager and map:GetPinFrameLevelsManager()
    if mgr and mgr.GetValidFrameLevel and self.qdLevel == "PIN_FRAME_LEVEL_AREA_POI" then
      for _, lvl in ipairs({ "PIN_FRAME_LEVEL_QUEST_BLOB", "PIN_FRAME_LEVEL_EVENT_OVERLAY" }) do
        local ok, v = pcall(mgr.GetValidFrameLevel, mgr, lvl)
        if ok and type(v) == "number" then pcall(self.UseFrameLevelType, self, lvl) self.qdLevel = lvl break end
      end
    end
    local canvas = map and map.GetCanvas and map:GetCanvas()
    local W = canvas and canvas.GetWidth and ns.Num(canvas:GetWidth()) or 1002
    local H = canvas and canvas.GetHeight and ns.Num(canvas:GetHeight()) or 668
    if W <= 0 or H <= 0 then W, H = 1002, 668 end
    -- (17.10., Daniel: "smooth the edges, pixelated does not look nice") soft round blobs (qd_blob: solid core, soft
    -- edge) on the spots, one every AREA_STEP of the radius so the cloud is even; together a soft area
    local R = AREA_RADIUS * 1.35 -- the blob's soft edge reaches a bit past the radius
    local ry = R * W / H
    local picks, step2 = {}, (R * AREA_STEP) ^ 2
    for _, p in ipairs(area.points) do
      local near = false
      for _, q in ipairs(picks) do
        if (p.x - q.x) ^ 2 + ((p.y - q.y) * H / W) ^ 2 < step2 then near = true break end
      end
      if not near then picks[#picks + 1] = p end
    end
    local x0, x1, y0, y1
    for _, p in ipairs(picks) do
      x0 = math.min(x0 or 1, p.x - R) x1 = math.max(x1 or 0, p.x + R)
      y0 = math.min(y0 or 1, p.y - ry) y1 = math.max(y1 or 0, p.y + ry)
    end
    self.rects = self.rects or {}
    local used = 0
    if x0 then
      local fw, fh = x1 - x0, y1 - y0
      self:SetSize(fw * W, fh * H)
      self:SetPosition(x0 + fw / 2, y0 + fh / 2)
      local r, g, b = QuestColor(area.questID)
      local d = 2 * R * W
      for _, p in ipairs(picks) do
        used = used + 1
        local t = self.rects[used]
        if not t then t = self:CreateTexture(nil, "ARTWORK") t:SetTexture(BLOB) self.rects[used] = t end
        t:ClearAllPoints()
        t:SetPoint("CENTER", self, "TOPLEFT", (p.x - x0) * W, -(p.y - y0) * H)
        t:SetSize(d, d)
        t:SetVertexColor(r, g, b, AREA_ALPHA)
        t:Show()
      end
    end
    for k = used + 1, #self.rects do self.rects[k]:Hide() end
    self.strips = used
    ns.lastAreaPin = self -- (/qd diag)
    if self.SetAlpha then self:SetAlpha(area.dimmed and 0.5 or 1) end
  end

  -- What the map draws (DonMap's provider calls these; protected, so an error here never breaks the map).
  -- The pins of one request: worked out once, by "same" or by "build" (from the event path's precomputed list if it has one).
  local curMap, curPins, curSig
  local function PinsOf(mapID)
    if precomputed and precomputed.mapID == mapID then
      local pc = precomputed
      precomputed = nil
      return pc.pins, pc.sig, true
    end
    precomputed = nil
    if ns.HarvestQuestLines then ns.HarvestQuestLines(mapID) end
    return ns.PinsForMap(mapID)
  end
  local function Canvas(map) return map.GetCanvasScale and ns.Value(map.GetCanvasScale, map) or nil end
  local opts = { templates = { QUEST_TEMPLATE, OBJECTIVE_TEMPLATE, AREA_TEMPLATE }, stats = stats }
  opts.ask = ns.Guard("map", function(prov, map, closed)
    ns.RedrawGameIfPending() -- (18.10.) the option went off: the game draws its markers again once
    MapCaller(closed)
    -- (23.10., Daniel's /qd mem: the map drew its pins also while closed) nothing to see: drawn when the map opens
    if (closed and not prov:Forced()) or prov:Off() then precomputed = nil end
  end)
  opts.removed = function() lastSig = nil end
  -- (23.10.) the map asks again (the game refreshes all its providers) and nothing changed: same map, pins, zoom steps
  -- (DonMap keeps them while all our pins are still on the canvas)
  -- (24.11.2026, Ruckler, laptop: "map ?" 9 times in 9 s with the map open, avg 28 ms, max 76) the game asks its
  -- providers again on its own (quest log, bags, the map's own refresh): the pins and their signature were worked out
  -- in that frame each time. Now, where the refresh can run in slices (ns.MapSliced), such a request keeps the pins
  -- and marks the map's part of the batched refresh: it works them out in slices and draws only when they changed (the
  -- same pins, at most a moment later). Our own requests come with their pins (precomputed) or say so (sameNow:
  -- options and commands, ns.RefreshPins); another map, zoom step or OpenMap state builds at once as before.
  opts.same = ns.Guard("map", function(prov, map, mapID)
    if not (precomputed and precomputed.mapID == mapID) and lastSig and not sameNow and ns.MapSliced()
        and ns.OpenMapEntrances() == lastOpenMap and ns.ClusterBucket(Canvas(map)) == objBucket
        and ZoomKey(objBucket) == lastZKey then
      stats.deferred = (stats.deferred or 0) + 1
      if ns.QueueRefresh then ns.QueueRefresh("map") end
      return true
    end
    local pins, sig, pre = PinsOf(mapID)
    curMap, curPins, curSig = mapID, pins, sig
    if pre or not lastSig then return false end
    if ns.OpenMapEntrances() ~= lastOpenMap then return false end -- (06.11.2026) OpenMap's stitched map came or went
    if ns.ClusterBucket(Canvas(map)) ~= objBucket then return false end
    if ZoomKey(objBucket) ~= lastZKey then return false end
    curSig = ns.PinsSignature(mapID, pins)
    return curSig == lastSig
  end)
  opts.kept = function()
    curMap, curPins, curSig = nil, nil, nil
    ns.QueueClearGamePOIs() -- (17.10.) option hideGamePOIs: the game drew its own markers again
  end
  opts.build = ns.Guard("map", function(prov, map, mapID)
    local pins, sig
    if curMap == mapID then pins, sig = curPins, curSig else pins, sig = PinsOf(mapID) end
    curMap, curPins, curSig = nil, nil, nil
    -- (1.21) quest givers with several quests: one pin (display only)
    -- (1.25) and no second "!" where the game draws one
    -- (1.3.5) dense objective dots: fewer markers (quest givers and turn-ins are never thinned)
    objBucket = ns.ClusterBucket(Canvas(map))
    local display, areas
    sig = sig or ns.PinsSignature(mapID, pins)
    local zkey = ZoomKey(objBucket)
    lastZKey = zkey
    if zoomCacheSig ~= mapID .. "#" .. tostring(sig) then zoomCache, zoomCacheSig, zoomCacheN = {}, mapID .. "#" .. tostring(sig), 0 end
    local cached = zoomCache[zkey]
    if cached then
      display, areas, objThinned = cached[1], cached[2], cached[3]
      stats.zoomCached = (stats.zoomCached or 0) + 1
    elseif ns.SymbolsOn() then
      -- (17.10.) symbols: each objective's groups of spots as one symbol with its area (zoom changes the groups)
      display, areas = ns.SymbolWorldObjectives(ns.DisplayQuestPins(pins, ns.ClusterDistance()), objBucket)
      objThinned = true
    else
      display = ns.ThinWorldObjectives(ns.DisplayQuestPins(pins, ns.ClusterDistance()), objBucket, ns.db.objectivePinSize or 12)
      local ts = ns.WorldThinStats()
      objThinned = ts.before > ts.after or ts.before > ns.WORLD_OBJECTIVE_BUDGET
    end
    if not cached then
      if zoomCacheN >= ZOOM_KEEP then zoomCache, zoomCacheN = {}, 0 end
      zoomCache[zkey] = { display, areas, objThinned }
      zoomCacheN = zoomCacheN + 1
    end
    for _, area in ipairs(areas or {}) do prov:Acquire(AREA_TEMPLATE, area) end
    ns.QueueClearGamePOIs() -- (17.10.) option hideGamePOIs
    -- (06.11.2026, Daniel: "Wenn dungeon Eingänge durch z.b. openmaps schon da sind. Keine doppelten machen") OpenMap
    -- draws every dungeon entrance on its stitched map (its Map/Dungeons.lua, always on): ours stay away there; the
    -- marked entrance (kind "entrance") and the minimap's stay
    lastOpenMap = ns.OpenMapEntrances()
    for _, pin in ipairs(display) do
      -- (1.3.5) dungeon entrances only with their option (the minimap has its own)
      if not (pin.kind == "dungeon" and (ns.db.dungeonPins == false or lastOpenMap)) then
        prov:Acquire(pin.kind == "objective" and OBJECTIVE_TEMPLATE or QUEST_TEMPLATE, pin)
      end
    end
    lastSig = sig
    -- (07.11.2026) does the game draw its own ? here (after its providers and DonMap's clearing ran)
    if ns.After then ns.After(0.3, function()
      ns.SafeCall("game quest pins", ns.CheckGameQuestPins)
      ns.SafeCall("turn-in above the game's !", ns.RaiseTurnInPins) -- (19.11.2026)
    end) end
    return true
  end)
  -- (1.3.5) zoomed: only when objective dots were thinned for another zoom step (the budget follows the zoom), and
  -- only when the rounded zoom step changed
  opts.zoomed = ns.Guard("map", function(prov, map, scale)
    local thin = objThinned and (ns.db.thinObjectives ~= false or ns.SymbolsOn())
    if not thin then return false end
    return ns.ClusterBucket(ns.Num(scale)) ~= objBucket
  end)
  if not (DonMapAPI and (DonMapAPI.version or 0) >= 4) then setupFailed = "old DonMap" return end
  provider = DonMapAPI.NewWorldProvider("questdon", opts)
  if not provider then setupFailed = true return end
  -- (10.11.2026) the map closed (the canvas tells its data providers): what was shown only for this look goes
  provider.OnHide = ns.Guard("map", function() if ns.MapClosed then ns.MapClosed() end end)
end

-- (17.10., Daniel: "the game's own markers are annoying, build the option in") Option hideGamePOIs (off): the game's
-- quest markers on the world map (the round objective markers and the blue quest areas) are taken away. No hook on
-- the game's code (Questdon's rule): after our own refresh of the map and after the quest events the game redraws
-- them on, its two quest providers are asked to remove their pins (a moment later, so theirs ran first). Turned
-- off, they are asked to draw again.
-- (DonMap M3b, 30.10.2026) the work is DonMap's (DonMapAPI.HideGameQuestMarks, WorldProvider.lua); Questdon says when
-- (the option) and which of the game's round markers stay (KeepPin), and draws the turn-ins itself when none can stay.
-- (18.10.) Of the game's round markers (QuestPinTemplate) the ? of finished quests stay: a pin is kept when its quest
-- is complete. true: keep it, false: remove it, nil: not to be told (the pin carries no quest): then everything goes as
-- before and Questdon draws the turn-in "?" itself (ns.gameKeepsTurnIns = false).
local function KeepPin(pin)
  local q = type(pin) == "table" and ns.Num(pin.questID)
  if not q then return nil end
  return ns.IsQuestComplete(q) and not ns.IsQuestFailed(q)
end
local function SetKeeps(v)
  if ns.gameKeepsTurnIns == v then return end
  ns.gameKeepsTurnIns = v
  -- Questdon's own turn-in marks follow. (23.10., /qd mem: "timer MapPins.lua:1452" about 300 KB at a time) only the
  -- world map, and only if its pins changed (was a full redraw of map, minimap and nameplates)
  if ns.QueueRefresh then ns.QueueRefresh("map") end
end
local DM = DonMapAPI and (DonMapAPI.version or 0) >= 4 and DonMapAPI -- DonMap 1.1 with M3b (## Dependencies)
if DM then
  DM.HideGameQuestMarks("questdon", {
    on = function() return ns.db and ns.db.hideGamePOIs and true or false end,
    keep = KeepPin, keeps = SetKeeps, keeping = function() return ns.gameKeepsTurnIns end, prefix = "Questdon",
  })
else -- an older DonMap: no map pins, nothing to clear
  local function None() return 0 end
  DM = { GameQuestProviders = function() return {} end, IsGameQuestTemplate = function() return false end,
    GameQuestMarkStats = function() return { providers = 0, templates = 0, runs = 0 } end, ClearGameQuestMarks = None,
    QueueClearGameQuestMarks = None, RedrawGameIfPending = None, ApplyGameQuestMarks = None,
    GameRedrawPending = function() return false end, HiddenGameBlobs = function() return {} end, GameMarkShown = function() return false end }
end
ns.GameQuestProviders = DM.GameQuestProviders -- (tests)
ns.IsGameQuestTemplate = DM.IsGameQuestTemplate -- (tests)
ns.GamePOIStats = DM.GameQuestMarkStats
ns.ClearGamePOIs = DM.ClearGameQuestMarks
ns.QueueClearGamePOIs = DM.QueueClearGameQuestMarks
ns.RedrawGameIfPending = DM.RedrawGameIfPending
ns.ApplyGamePOIs = DM.ApplyGameQuestMarks
ns.GameRedrawPending = DM.GameRedrawPending -- (tests)
ns.HiddenGameBlobs = DM.HiddenGameBlobs -- (tests)
ns.GameMarkShown = DM.GameMarkShown -- (tests)

function ns.MapProvider() return provider end -- (tests)
-- For /qd diag: are the map pins set up?
function ns.MapPinsState()
  if provider then return "ready" end
  if setupFailed == "old DonMap" then return "DonMap too old (update DonMap)" end
  if setupFailed then return "failed (AddDataProvider)" end
  if not WorldMapFrame then return "waiting for the world map" end
  return "not available (map APIs missing)"
end

-- (1.2) A click on a pin points the arrow there and switches the arrow on if
-- it was off (before, the click set the target of a hidden arrow).
-- (Questdon review 4) pin: the clicked pin, so the target knows its quest and goes once the quest no longer needs it
-- (24.11.2026, Daniel: "das Questziel von mir herausheben") the quest pin ("!" or "?", also a marker of several quests)
-- the arrow leads to: same quest, and a "?" only while the quest is in the log, a "!" only while it is not.
-- Objective dots stay as they are (the arrow's objective target is often a whole area).
function ns.ArrowTargetPinKey()
  local t = ns.ArrowTarget and ns.ArrowTarget()
  local q = type(t) == "table" and ns.Num(t.questID)
  if not q then return nil end
  return q .. (ns.InQuestLog(q) and ":log" or ":new")
end
function ns.IsArrowTargetPin(pin)
  if type(pin) ~= "table" then return false end
  local t = ns.ArrowTarget and ns.ArrowTarget()
  local q = type(t) == "table" and ns.Num(t.questID)
  if not q then return false end
  for _, m in ipairs(type(pin.group) == "table" and pin.group or { pin }) do
    if type(m) == "table" and ns.Num(m.questID) == q then
      if m.kind == "turnin" and ns.InQuestLog(q) then return true end
      if m.kind == "available" and not ns.InQuestLog(q) then return true end
    end
  end
  return false
end

function ns.PointArrowFromPin(mapID, x, y, label, kind, pin)
  if not (mapID and x and y and ns.SetArrowTarget) then return end
  ns.EnsureArrow()
  local questID = type(pin) == "table" and not pin.group and ns.Num(pin.questID) or nil
  local spot = type(pin) == "table" and not pin.group and (pin.creature ~= nil or pin.index ~= nil) and pin or nil
  ns.SetArrowTarget(mapID, x, y, label, kind or (type(pin) == "table" and pin.kind) or nil, questID, spot)
end
-- (Questdon review 3) the arrow window switched on only when nothing shows the way yet (the quest list's compass or a
-- guide): a pin click, /qd next, a zone list entry or a dungeon mark switched it on for good, two arrows from then on
function ns.EnsureArrow()
  if ns.db.arrow or ns.db.noWay or (ns.ArrowRuns and ns.ArrowRuns()) then return end -- (05.11.2026) "None" stays
  ns.db.arrow = true
  if ns.ApplyArrow then ns.ApplyArrow() end
end

function ns.RefreshPins()
  if ns.ForgetAvailable then ns.ForgetAvailable() end -- (24.10.) options, /qd, hiding a quest
  if not provider then Setup() end -- world map loaded later than expected
  if provider and provider:GetMap() and WorldMapFrame:IsShown() then
    sameNow = true
    provider:RefreshAllData()
    sameNow = nil
  end
  -- (1.21) options and /qd commands: the minimap pins follow
  if ns.RefreshMinimapPins then ns.RefreshMinimapPins(true) end
  -- (1.22) and the nameplate icons
  if ns.RefreshNameplates then ns.RefreshNameplates() end
end

-- (1.17) Event path: rebuild only when the pins changed.
-- (1.20) In combat the pins stay as they are (before, every quest log update
-- in combat removed them all); the refresh after combat (PLAYER_REGEN_ENABLED)
-- compares the signature and rebuilds only if something changed.
-- (24.11.2026, Ruckler, laptop: "refresh map" avg 18.7 ms, max 35.6) where the game has the clock for it, the batched
-- refresh's part runs in slices (mapJob, a coroutine, MAP_SLICE_MS a frame): quest lines and base pins, the objective
-- dots, the signature, then the drawing with the pins worked out (one step: the map never shows half of them). Each
-- step after a pause checks that the same map is still open and no fight began; a new refresh starts anew. Pauses
-- only in RefreshIfChanged and BuildPins themselves, never under a pcall (tools/yieldcheck.lua).
local MAP_SLICE_MS = 4
local mapJob -- { co, t0 = the slice's start (ms), slices, part = the step being worked out }
function ns.MapSliced()
  return type(debugprofilestop) == "function" and C_Timer ~= nil and C_Timer.After ~= nil and type(coroutine) == "table"
end
-- stats.stepMs: the longest time of each step (ms, /qd diag and the tests)
local function StepTime(j, now)
  local sm = stats.stepMs
  if not sm then sm = {} stats.stepMs = sm end
  local d = now - (j.pt or j.t0)
  if d > (sm[j.part] or 0) then sm[j.part] = d end
end
local function MapPause(part)
  local j = mapJob
  if not j or coroutine.running() ~= j.co then return end
  local now = debugprofilestop()
  StepTime(j, now)
  if now - j.t0 >= MAP_SLICE_MS then
    j.slices = j.slices + 1
    coroutine.yield()
    j.pt = j.t0
  else
    j.pt = now
  end
  j.part = part or j.part -- (24.11.2026) a pause without a step name (Questdon's own in the base) keeps the step
end
local function JobCanvas(map) return map.GetCanvasScale and ns.Value(map.GetCanvasScale, map) or nil end
-- the display list of the current zoom step into the zoom cache, as the build would make it (it then draws from the
-- cache): the grouped markers, a pause, the thinned dots with pauses between the steps. Symbols: left to the build.
local function PrepareDisplay(mapID, pins, sig)
  if ns.SymbolsOn() then return end
  local map = provider:GetMap()
  local bucket = ns.ClusterBucket(JobCanvas(map))
  local zkey, key = ZoomKey(bucket), mapID .. "#" .. tostring(sig)
  if zoomCacheSig == key and zoomCache[zkey] then return end
  local grouped = ns.DisplayQuestPins(pins, ns.ClusterDistance())
  MapPause("thin")
  local display = ns.ThinWorldObjectives(grouped, bucket, ns.db.objectivePinSize or 12, MapPause)
  local ts = ns.WorldThinStats()
  local thinned = ts.before > ts.after or ts.before > ns.WORLD_OBJECTIVE_BUDGET
  if zoomCacheSig ~= key then zoomCache, zoomCacheSig, zoomCacheN = {}, key, 0 end
  if zoomCacheN >= ZOOM_KEEP then zoomCache, zoomCacheN = {}, 0 end
  zoomCache[zkey] = { display, nil, thinned }
  zoomCacheN = zoomCacheN + 1
  stats.prepared = (stats.prepared or 0) + 1
end
local function MapStill(mapID)
  return provider and provider:GetMap() and WorldMapFrame:IsShown() and not provider:Off() and not InCombatLockdown()
    and ns.Num(provider:GetMap():GetMapID()) == mapID
end
local function RefreshIfChanged()
  if not provider then Setup() end
  if not (provider and provider:GetMap() and WorldMapFrame:IsShown()) then return end
  if provider:Off() then return end -- (review) /donmap questdon off: nothing to work out
  if InCombatLockdown() then stats.combat = (stats.combat or 0) + 1 return end
  local mapID = ns.Num(provider:GetMap():GetMapID())
  if mapID then
    if ns.HarvestQuestLines then ns.HarvestQuestLines(mapID) end
    local inJob = mapJob ~= nil and coroutine.running() == mapJob.co
    local pins
    if inJob then
      MapPause("base")
      if not MapStill(mapID) then return end
      pins = BuildPins(mapID, MapPause)
      MapPause("signature")
      if not MapStill(mapID) then return end
    else
      pins = ns.PinsForMap(mapID)
    end
    local sig = ns.PinsSignature(mapID, pins, inJob and MapPause or nil)
    if inJob and not MapStill(mapID) then return end
    if lastSig and sig == lastSig and ZoomKey(objBucket) == lastZKey then stats.skipped = stats.skipped + 1 return end
    if inJob then
      MapPause("display")
      if not MapStill(mapID) then return end
      PrepareDisplay(mapID, pins, sig)
      MapPause("draw")
      if not MapStill(mapID) then return end
    end
    precomputed = { mapID = mapID, pins = pins, sig = sig }
  end
  provider:RefreshAllData()
end
-- one slice of the refresh on the way (a timer of the next frame runs the next one)
local function MapJobStep()
  local j = mapJob
  if not j then return end
  j.t0 = debugprofilestop()
  local ok, err = coroutine.resume(j.co)
  if mapJob ~= j then return end -- another refresh started meanwhile
  if debugprofilestop() - j.t0 >= 8 and type(rawget(_G, "DonMonitorDB")) == "table" then ns.slowDetail = "map " .. tostring(j.part) end
  if not ok then mapJob = nil error(err, 0) end
  if coroutine.status(j.co) ~= "dead" then ns.After(0, MapJobStep) return end
  StepTime(j, debugprofilestop())
  mapJob = nil
  stats.sliced = (stats.sliced or 0) + 1
  stats.slices = (stats.slices or 0) + j.slices
end
-- the batched refresh's part: in slices where it can (the map open), else at once as before
local function RefreshPart()
  if not (ns.MapSliced() and provider and provider:GetMap() and WorldMapFrame:IsShown()) then
    mapJob = nil
    return RefreshIfChanged()
  end
  local j = { slices = 0, part = "lines" }
  j.co = coroutine.create(RefreshIfChanged)
  mapJob = j
  MapJobStep()
end
ns.MapJob = function() return mapJob end -- (tests)
ns.RefreshPinsIfChanged = RefreshIfChanged

-- (1.23) Event path: one batched refresh for all quest displays (Core.lua).
ns.RegisterRefresh("map", RefreshPart)
local function Queue() ns.QueueRefresh("map") end

-- (1.23) Learning (accept, turn-in) and other modules: the same batched
-- refresh for map, minimap and nameplates instead of a forced rebuild of all
-- three right before the QUEST_LOG_UPDATE batch does the same work again.
function ns.QueuePinRefresh()
  ns.QueueRefresh("map", "minimap", "nameplates")
end

ns.OnInit(Setup)
-- If the world map is loaded later (load on demand), set up then.
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", ns.Guard("ADDON_LOADED", function(self, _, name)
  if name == "Blizzard_WorldMap" and ns.db then
    self:UnregisterEvent("ADDON_LOADED")
    Setup()
  end
end))
ns.On("PLAYER_REGEN_ENABLED", Queue)
-- (1.3.5) the build right before combat (map closed, set to the player's zone) is DonMap's (WorldProvider.lua)
ns.On("QUEST_LOG_UPDATE", Queue)
-- (Questdon review 5) "Only for tracked quests": another quest tracked changes which dots show (the minimap kept the
-- old quest's dots until a quest or bag event)
for _, e in ipairs({ "SUPER_TRACKING_CHANGED", "QUEST_WATCH_LIST_CHANGED" }) do
  ns.On(e, function() if ns.db and ns.db.objectivePinsTrackedOnly then ns.RefreshPins() end end)
end
-- (21.11.2026, Ruckler) not for the answers of DonData's background level walk (ns.LevelScanAsked, DonData/Engine/Levels.lua)
ns.On("QUEST_DATA_LOAD_RESULT", function(_, questID)
  if ns.LevelScanAsked and ns.LevelScanAsked(questID) == true then return end
  Queue()
end)
ns.On("QUESTLINE_UPDATE", Queue)
ns.On("PLAYER_LEVEL_UP", Queue) -- (1.23) new level: other quests available (minimap and nameplates did this already)
ns.On("BAG_UPDATE_DELAYED", function()
  -- only matters while a pin depends on the bags (cheap check, queued refresh)
  if WorldMapFrame and WorldMapFrame:IsShown() then Queue() end
end)
