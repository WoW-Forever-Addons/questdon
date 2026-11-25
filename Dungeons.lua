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

-- (31.10.2026, DONCORE_PLAN.md "DonData Lese-Engine") the dungeon of a quest, the dungeon's name and its level range
-- (ns.QuestDungeon, DungeonName, DungeonLevelRange, DungeonTableRange, DungeonGameRange, DungeonMinLevel, DungeonFit,
-- DungeonGameLevelStats, ResetDungeonGameLevels) are DonData's now: DonData/Engine/Dungeons.lua, one namespace.
local GAME_MAP = ns.DUNGEON_GAME_MAP or {}

local function Now() return ns.Num(ns.Value(GetTime)) or 0 end
local function Str(v) return type(v) == "string" and ns.Usable(v) and v ~= "" and v or nil end

-- The dungeon an activity name belongs to: the longest dungeon name it starts with.
local function ByName(name, names)
  local best, bestLen
  local low = name:lower()
  local short = low:gsub("^the%s+", "")
  for inst, list in pairs(names) do
    for _, n in ipairs(list) do
      if (low:sub(1, #n) == n or short:sub(1, #n) == n) and (not bestLen or #n > bestLen) then best, bestLen = inst, #n end
    end
  end
  return best
end

---------------------------------------------------------------------------
-- (1.3.5) Entrance of a dungeon: the game's own (C_EncounterJournal.GetDungeonEntrancesForMap, the zones of
-- Kalimdor and the Eastern Kingdoms read once per session, matched by name), else (1.3.6) the list of
-- Data/Dungeon_Entrances.lua, else the data's (ns.ATT_DUNGEONS). Data entrances on maps that are no zone (Blackrock Mountain 33/35, Ahn'Qiraj 327,
-- Uldaman's 16) are left out: the arrow and the pins need the zone's coordinates.
---------------------------------------------------------------------------
local NOT_ZONE = { [16] = true, [33] = true, [35] = true, [327] = true }
local CONTINENTS = { 1414, 1415 }
local ej
local ejStats = { zones = 0, entrances = 0, matched = 0 }
function ns.DungeonEntranceStats() return ejStats end
local function ScanEntrances()
  if ej then return ej end
  ej = {}
  local api = C_EncounterJournal
  if type(api) ~= "table" or type(api.GetDungeonEntrancesForMap) ~= "function" then return ej end
  local zones, seen = {}, {}
  local zoneType = Enum and Enum.UIMapType and ns.Num(Enum.UIMapType.Zone) or 3
  for _, cont in ipairs(CONTINENTS) do
    local ok, kids = false, nil
    if C_Map and type(C_Map.GetMapChildrenInfo) == "function" then ok, kids = pcall(C_Map.GetMapChildrenInfo, cont, zoneType, true) end
    for _, k in ipairs(ok and type(kids) == "table" and kids or {}) do
      local m = type(k) == "table" and ns.Num(k.mapID)
      if m and not seen[m] then seen[m] = true zones[#zones + 1] = m end
    end
  end
  for _, d in pairs(D) do
    local m = d[EMAP]
    if m and not NOT_ZONE[m] and not seen[m] then seen[m] = true zones[#zones + 1] = m end
  end
  for _, list in pairs(ns.DUNGEON_ENTRANCES or {}) do
    for _, p in ipairs(list) do
      local m = ns.Num(p[1])
      if m and not seen[m] then seen[m] = true zones[#zones + 1] = m end
    end
  end
  table.sort(zones)
  local names = {}
  for inst, d in pairs(D) do
    local list = {}
    for _, n in ipairs({ Str(ns.DungeonName(inst)), Str(d[NAME_EN]) }) do
      local low = n:lower()
      list[#list + 1] = low
      local short = low:gsub("^the%s+", "")
      if short ~= low then list[#list + 1] = short end
    end
    names[inst] = list
  end
  for _, m in ipairs(zones) do
    ejStats.zones = ejStats.zones + 1
    local ok, list = pcall(api.GetDungeonEntrancesForMap, m)
    for _, e in ipairs(ok and type(list) == "table" and list or {}) do
      if type(e) == "table" then
        ejStats.entrances = ejStats.entrances + 1
        local name = Str(e.name)
        if not name and type(EJ_GetInstanceInfo) == "function" and ns.Num(e.journalInstanceID) then
          local okN, n = pcall(EJ_GetInstanceInfo, e.journalInstanceID)
          name = okN and Str(n) or nil
        end
        local x, y
        local pos = e.position
        if type(pos) == "table" then
          if type(pos.GetXY) == "function" then
            local okP, px, py = pcall(pos.GetXY, pos)
            if okP then x, y = ns.Num(px), ns.Num(py) end
          end
          if not x then x, y = ns.Num(pos.x), ns.Num(pos.y) end
        end
        local inst = name and ByName(name, names)
        if inst and x and y and x > 0 and y > 0 and not ej[inst] then
          ej[inst] = { m, x, y, ns.Num(e.journalInstanceID) } -- (1.3.5) the journal ID for its picture
          ejStats.matched = ejStats.matched + 1
        end
      end
    end
  end
  return ej
end
function ns.ResetDungeonEntrances() ej = nil end -- (tests)

-- (1.3.6) Every entrance of a dungeon: { { mapID, x, y (0-1), source }, ... }, main one first. The game's
-- journal, else the list of Data/Dungeon_Entrances.lua (where you walk in, Forever's map coordinates, two
-- ways in for Uldaman, Stratholme and Blackrock Mountain), else All The Things' point on a zone map.
-- (1.3.6) Entries carry two more fields: [5] = how many other players confirmed this way in (QuestdonNet,
-- guild, group; Entrances.lua), [6] = true when the player entered here. A learned spot farther than
-- LEARN_NEAR from every listed one is another way in: own ("learned") or confirmed by others ("shared").
local LEARN_NEAR = 0.03
local function Near(p, m, x, y) return p[1] == m and math.abs(p[2] - x) <= LEARN_NEAR and math.abs(p[3] - y) <= LEARN_NEAR end
function ns.DungeonEntrances(inst)
  local out = {}
  local e = inst and ScanEntrances()[inst]
  if e then out[1] = { e[1], e[2], e[3], "game" } return out end
  local list = inst and ns.DUNGEON_ENTRANCES and ns.DUNGEON_ENTRANCES[inst]
  if type(list) == "table" then
    for _, p in ipairs(list) do
      local m, x, y = ns.Num(p[1]), ns.Num(p[2]), ns.Num(p[3])
      if m and x and y then out[#out + 1] = { m, x / 100, y / 100, "list" } end
    end
  end
  if #out == 0 then
    local d = D[inst]
    if d and d[EMAP] and d[EX] and d[EY] and not NOT_ZONE[d[EMAP]] then out[1] = { d[EMAP], d[EX] / 100, d[EY] / 100, "data" } end
  end
  -- learned in the game: own, and what others confirmed.
  -- (22.11.2026, Daniel with a picture of three rings at Uldaman: "sowas darf nicht passieren") The listed
  -- entrances are checked by hand; a learned spot is the player's position up to FRESH seconds before the load
  -- (Entrances.lua), deep in a long cave tunnel it lies well off the door. With listed entrances a learned or shared
  -- spot only confirms the nearest listed one on its map and never adds a ring of its own.
  local checked = #out > 0 and out[1][4] == "list"
  local function Merge(m, x, y, source, n, mine)
    local hit
    for _, p in ipairs(out) do
      if Near(p, m, x, y) then hit = p break end
    end
    if not hit and checked then
      local best
      for _, p in ipairs(out) do
        local d = p[1] == m and (p[2] - x) ^ 2 + (p[3] - y) ^ 2
        if d and (not best or d < best) then hit, best = p, d end
      end
      if not hit then return end
    end
    if hit then
      if mine then hit[6] = true end
      if n then hit[5] = math.max(hit[5] or 0, n) end
      return
    end
    out[#out + 1] = { m, x, y, source, n, mine or nil }
  end
  local lm, lx, ly
  if ns.LearnedEntrance then lm, lx, ly = ns.LearnedEntrance(inst) end
  if lm and lx and ly then Merge(lm, lx, ly, "learned", nil, true) end
  for _, s in ipairs(ns.SharedEntrances and ns.SharedEntrances(inst) or {}) do Merge(s[1], s[2], s[3], "shared", s[4]) end
  return out
end

-- Entrance: mapID, x, y (0-1), source ("game", "list" or "data"), or nil. With several ways in: the
-- nearest to the player (same continent), else the one on the player's map, else the main one.
function ns.DungeonEntrance(inst)
  local all = ns.DungeonEntrances(inst)
  local best = all[1]
  if #all > 1 then
    local here = C_Map and ns.Num(ns.Value(C_Map.GetBestMapForUnit, "player"))
    local bestD
    for _, p in ipairs(all) do
      local dist = ns.DistanceAndBearing and ns.DistanceAndBearing({ mapID = p[1], x = p[2], y = p[3] })
      dist = ns.Num(dist)
      if dist and (not bestD or dist < bestD) then best, bestD = p, dist end
    end
    if not bestD and here then
      for _, p in ipairs(all) do if p[1] == here then best = p break end end
    end
  end
  if best then return best[1], best[2], best[3], best[4] end
end

---------------------------------------------------------------------------
-- (1.3.5, Daniel 10.10.) "Mark entrance": the arrow points at the entrance, and an own entrance pin stands
-- on the world map and the minimap (MapPins.lua, Minimap.lua). One mark at a time, kept for this session
-- only. It goes away within MARK_NEAR yards of the entrance, inside that dungeon, after MARK_TIME seconds,
-- on a right-click on its pin or a second click on the button. If the arrow still points at the
-- entrance then, it goes back to its own target (tracked quest, next quest).
---------------------------------------------------------------------------
local MARK_NEAR, MARK_TIME = 40, 1800
local mark, markTicker
local markStats = { set = 0, removed = 0, last = nil }
function ns.EntranceMarkStats() return markStats end
function ns.EntranceMark() return mark end

local function RefreshMarkViews()
  if ns.RefreshPins then ns.RefreshPins() end
  if ns.UpdateZoneQuests then ns.UpdateZoneQuests() end
end

function ns.RemoveEntranceMark(reason)
  if not mark then return false end
  mark = nil
  if markTicker then markTicker:Cancel() markTicker = nil end
  markStats.removed, markStats.last = markStats.removed + 1, reason or "?"
  local t = ns.ArrowTarget and ns.ArrowTarget()
  if t and t.kind == "entrance" and ns.ClearArrow then
    ns.ClearArrow()
    if ns.UpdateArrowTarget then ns.UpdateArrowTarget() end
  end
  RefreshMarkViews()
  return true
end

local function CheckMark()
  if not mark then return end
  if Now() - mark.at >= MARK_TIME or Now() < mark.at then ns.RemoveEntranceMark("time") return end
  if ns.CurrentDungeon() == mark.inst then ns.RemoveEntranceMark("inside") return end
  local dist = ns.DistanceAndBearing and ns.DistanceAndBearing(mark)
  if dist and dist <= MARK_NEAR then ns.RemoveEntranceMark("arrived") end
end
ns.CheckEntranceMark = CheckMark

-- Marks the entrance of inst (replacing another mark). true if an entrance is known.
function ns.MarkEntrance(inst)
  local m, x, y, source = ns.DungeonEntrance(inst)
  if not m then return false end
  if mark then ns.RemoveEntranceMark("replaced") end
  local name = ns.DungeonName(inst)
  mark = { inst = inst, mapID = m, x = x, y = y, at = Now(), name = name, source = source }
  markStats.set = markStats.set + 1
  if ns.SetArrowTarget then
    ns.EnsureArrow() -- (review 3) not a second arrow next to the list's compass
    ns.SetArrowTarget(m, x, y, L["Entrance: %s"]:format(name), "entrance")
  end
  if not markTicker then markTicker = ns.NewTicker(1, CheckMark) end
  RefreshMarkViews()
  return true
end

-- The button: marks, or removes the mark of this dungeon. true if a mark is set now.
function ns.ToggleEntranceMark(inst)
  if mark and mark.inst == inst then ns.RemoveEntranceMark("button") return false end
  return ns.MarkEntrance(inst)
end

-- The pin of the mark for a map (MapPins.lua), or nil.
function ns.EntrancePin(mapID)
  if mark and mark.mapID == mapID then
    return { kind = "entrance", inst = mark.inst, name = mark.name, x = mark.x, y = mark.y }
  end
end

-- (round 8, Daniel 10.10.: "the left click should open the journal on the marked pin too") The marked
-- pin: the dungeon's lines (level, quests, fit), a click opens the dungeon journal, a right-click removes
-- the mark; the arrow already points there.
function ns.EntrancePinTooltip(pin)
  local _, lines = ns.DungeonPinTooltip(pin)
  return ns.DungeonIconTag(pin and pin.inst) .. L["Entrance: %s"]:format(pin and pin.name or "?"), lines or {},
    L["Click: dungeon journal, right-click: remove the mark"]
end

---------------------------------------------------------------------------
-- (1.3.5, Daniel 10.10.: "mark every entrance like this, and a click opens our dungeon journal") Every
-- dungeon and raid with a known entrance gets a pin on the world map (option dungeonPins) and, within
-- MINIMAP_YARDS, on the minimap (option dungeonPinsMinimap). Its tooltip: name, level range, your quests
-- there, how it fits your level. Click: the quest book on the Dungeons tab with that dungeon; right-click:
-- the entrance mark (arrow, highlighted pin). While the mark of a dungeon is set, its pin is the mark's
-- own pin (brighter; right-click removes the mark).
---------------------------------------------------------------------------
ns.DUNGEON_PIN_MINIMAP_YARDS = 300

-- Your quests of a dungeon: total (those for you), done, ready (in the log or to take now).
function ns.DungeonQuestCounts(inst)
  local total, done, ready = 0, 0, 0
  for _, id in ipairs(ns.DungeonQuestIDs(inst)) do
    local group = ns.ZoneQuestStatus(id)
    if group then
      total = total + 1
      if group == "done" then done = done + 1 elseif group == "log" or group == "available" then ready = ready + 1 end
    end
  end
  return total, done, ready
end

-- "fits your level" / "in n levels" (red) / "below your level", with its colour; nil without a range.
function ns.DungeonFitText(inst, level)
  local fit, n = ns.DungeonFit(inst, level)
  if fit == "fits" then return L["fits your level"], "good" end
  if fit == "later" then return n == 1 and L["in 1 level"] or L["in %d levels"]:format(n), "critical" end
  if fit == "below" then return L["below your level"], "textHint" end
  return nil, "textHint"
end

-- The entrance pins of a map: { { kind = "dungeon", inst, name, x, y }, ... } (not the one that is marked).
function ns.DungeonEntrancePins(mapID)
  local list = {}
  -- for the world map (option dungeonPins) and the minimap (dungeonPinsMinimap, which filters by distance)
  if not (mapID and ns.db and (ns.db.dungeonPins ~= false or ns.db.dungeonPinsMinimap ~= false)) then return list end
  for inst in pairs(D) do
    for _, p in ipairs(ns.DungeonEntrances(inst)) do
      local isMark = mark and mark.inst == inst and mark.mapID == p[1] and math.abs(mark.x - p[2]) < 1e-6 and math.abs(mark.y - p[3]) < 1e-6
      if p[1] == mapID then
        list[#list + 1] = { kind = "dungeon", inst = inst, name = ns.DungeonName(inst), x = p[2], y = p[3],
          source = p[4], confirmed = p[5], mine = p[6], isMark = isMark or nil }
      end
    end
  end
  table.sort(list, function(a, b)
    if a.inst ~= b.inst then return a.inst < b.inst end
    return a.x < b.x
  end)
  -- (23.11.2026, Daniel with Blackrock Mountain on Searing Gorge and the Burning Steppes: "Ein Ring je
  -- Eingang") dungeons sharing one way in (Blackrock Mountain, the Scarab Gate) get ONE pin there: the
  -- lowest dungeon leads (click, right-click), the tooltip lists them all (ns.DungeonPinTooltip). Was
  -- (1.3.6) one pin each, side by side. While one of them is marked, the mark's pin stands for the way in.
  local groups, order = {}, {}
  for _, p in ipairs(list) do
    local k = math.floor(p.x * 200 + 0.5) .. ":" .. math.floor(p.y * 200 + 0.5)
    if not groups[k] then groups[k] = {} order[#order + 1] = k end
    table.insert(groups[k], p)
  end
  local function Low(inst) return ns.DungeonLevelRange(inst) or 999 end
  local out = {}
  for _, k in ipairs(order) do
    local g = groups[k]
    if #g > 1 then
      table.sort(g, function(a, b)
        local la, lb = Low(a.inst), Low(b.inst)
        if la ~= lb then return la < lb end
        return a.inst < b.inst
      end)
      local lead, insts, names = g[1], {}, {}
      for i, p in ipairs(g) do insts[i] = p.inst names[i] = p.name or "?" end
      lead.insts = insts
      lead.name = ns.SharedEntranceName(insts) or table.concat(names, " / ")
      for _, p in ipairs(g) do lead.confirmed = lead.confirmed or p.confirmed lead.mine = lead.mine or p.mine end
      local marked = false
      for _, p in ipairs(g) do marked = marked or p.isMark end
      if not marked then out[#out + 1] = lead end
    elseif not g[1].isMark then
      out[#out + 1] = g[1]
    end
  end
  list = out
  return list
end

-- The client's own name of the place several dungeons share (AreaTable: Blackrock Mountain 25, Gates of
-- Ahn'Qiraj 3478), in the game's language; nil without it.
local SHARED_AREAS = { [228] = 25, [229] = 25, [742] = 25, [743] = 3478, [744] = 3478 }
function ns.SharedEntranceName(insts)
  local area = insts and insts[1] and SHARED_AREAS[insts[1]]
  local get = area and C_Map and C_Map.GetAreaInfo
  if not get then return nil end
  local ok, name = pcall(get, area)
  return ok and Str(name) or nil
end

local function FitColored(inst)
  local fit, color = ns.DungeonFitText(inst)
  if not fit then return nil end
  local c = ns.Style and ns.Style.COLORS and ns.Style.COLORS[color]
  return (c and c.hex) and ("|c" .. c.hex .. fit .. "|r") or fit
end

local function QuestLine(inst)
  local total, done, ready = ns.DungeonQuestCounts(inst)
  local q = L["%d of %d quests done"]:format(done, total)
  if ready > 0 then q = q .. "  ·  " .. L["%d ready"]:format(ready) end
  return q
end

function ns.DungeonPinTooltip(pin)
  -- (23.11.2026) one pin for a shared way in: each dungeon a heading with its level, then its quests.
  -- Daniel 23.11. with the Blackrock Mountain tooltip: "diese kleinen bilderchen und wie das aufgebaut ist,
  -- hätte ich gerne bei jedem instanzeingang": a single dungeon the same way (picture, name, level; quests, fit)
  local insts = pin and pin.insts and #pin.insts > 1 and pin.insts or (pin and pin.inst and { pin.inst })
  if insts then
    local lines = {}
    for _, inst in ipairs(insts) do
      local lo, hi = ns.DungeonLevelRange(inst)
      local head = ns.DungeonIconTag(inst) .. "|cffffd100" .. (ns.DungeonName(inst) or "?") .. "|r"
      if lo then head = head .. "  " .. L["Level %d-%d"]:format(lo, hi or lo) end
      lines[#lines + 1] = head
      local q = QuestLine(inst)
      local fit = FitColored(inst)
      if fit then q = q .. "  ·  " .. fit end
      lines[#lines + 1] = q
    end
    -- (1.3.6, Daniel 10.10.: "tooltips must not be overloaded") whether the game confirmed an entrance stays
    -- out of the tooltip: /qd dungeonlevels reports it
    return ns.DungeonIconTag(pin.inst) .. (pin.name or ns.DungeonName(pin.inst) or "?"), lines,
      L["Click: dungeon journal, right-click: arrow"]
  end
  return "?", {}, L["Click: dungeon journal, right-click: arrow"]
end

-- Click on a pin: the quest book on the Dungeons tab with this dungeon. The book is an own frame
-- (not protected): it opens in combat too.
function ns.OpenDungeonJournal(inst)
  if not inst then return false end
  if ns.OpenQuestBook then ns.OpenQuestBook("dungeons") end
  if ns.QuestBookSelectDungeon then ns.QuestBookSelectDungeon(inst) end
  return true
end

-- Right-click on a pin: the entrance mark (a second right-click, on the mark's pin, removes it).
function ns.DungeonPinRightClick(inst)
  if mark and mark.inst == inst then return ns.RemoveEntranceMark("pin") and false end
  return ns.MarkEntrance(inst)
end

---------------------------------------------------------------------------
-- (1.3.5, Daniel 10.10.: "a small fitting picture of the instance") The dungeon's picture in the round
-- badges of the quest book and the entrance tooltips: the game client's own art, referenced at runtime,
-- no file shipped. Order: the Encounter Journal's button image (EJ_GetInstanceInfo; the journal ID from
-- the entrance scan or C_EncounterJournal.GetInstanceForGameMap), the Dungeon Finder's icon
-- (GetLFGDungeonInfo: textureFilename, matched by its map ID or name, read once), the known LFG icon
-- paths of the classic dungeons (not shipped files, the client's), else none (the badge shows the
-- level). A path the client does not have (GetFileIDFromPath) or a texture that does not take it
-- (ns.DungeonIconFailed) counts as none.
---------------------------------------------------------------------------
-- (23.11.2026) The chain itself (journal, Dungeon Finder, known LFG paths, icons of the client's icon set, every path checked)
-- is DonCore's Art module now, shared with Guildon Groups (Daniel: "Gleiches fertig aus dem DonCore-Kit, nie je Addon
-- nachbauen"). Questdon gives it the journal ID of the entrance scan, the game map and both names, and keeps its own
-- session state: the pictures a texture refused (ns.DungeonIconFailed) and the counts for /qd dungeonlevels.
local Art = LibStub("DonCore-1.0"):Get("Art", 2)
ns.DUNGEON_ICON_CANDIDATES = Art and Art.ICON_CANDIDATES or {} -- (tests)
local icons, iconFailed = {}, {}
local iconStats = { journal = 0, lfg = 0, known = 0, icon = 0, none = 0, failed = 0 }
function ns.DungeonIconStats() return iconStats end

-- The picture of a dungeon: texture (file ID or path), source ("journal", "lfg", "known", "icon"), or nil.
function ns.DungeonIcon(inst)
  if not inst or iconFailed[inst] then return nil end
  local c = icons[inst]
  if c ~= nil then if c then return c[1], c[2] end return nil end
  local tex, source
  if Art then
    local e = ScanEntrances()[inst]
    local names = {}
    for _, n in ipairs({ Str(ns.DungeonName(inst)) or false, D[inst] and Str(D[inst][NAME_EN]) or false }) do
      if n then names[#names + 1] = n end
    end
    tex, source = Art.DungeonIcon(inst, names, GAME_MAP[inst], e and e[4])
  end
  icons[inst] = tex and { tex, source } or false
  iconStats[tex and source or "none"] = iconStats[tex and source or "none"] + 1
  if tex then return tex, source end
  return nil
end
-- A texture did not take the picture: the level from now on (this session).
function ns.DungeonIconFailed(inst)
  if inst and not iconFailed[inst] then iconFailed[inst] = true iconStats.failed = iconStats.failed + 1 end
end
function ns.ResetDungeonIcons() icons, iconFailed = {}, {} if Art then Art.ResetIcons() end end -- (tests)
-- (round 8) For /qd dungeonlevels: where the picture of inst comes from ("journal", "lfg", "known", "icon",
-- "failed": the texture did not take it, "none") and the texture.
function ns.DungeonIconSource(inst)
  if iconFailed[inst] then return "failed" end
  local tex, source = ns.DungeonIcon(inst)
  return tex and source or "none", tex
end

-- "|T...|t " for a tooltip title, or "".
function ns.DungeonIconTag(inst, size)
  local tex, source = ns.DungeonIcon(inst)
  if not tex then return "" end
  size = size or 16
  -- (round 8) an icon of the icon set: without its dark frame (as the game crops its icons)
  if source == "icon" then return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t "):format(tostring(tex), size, size) end
  return ("|T%s:%d:%d|t "):format(tostring(tex), size, size)
end

---------------------------------------------------------------------------
-- (1.3.5, Daniel 10.10.: "next to it a button 'Show on map'") The world map on the entrance's zone, its
-- pin pulsing for HIGHLIGHT_SECS (MapPins.lua). OpenWorldMap is the client's documented call; in
-- combat addons may not open the map: then one chat line instead.
---------------------------------------------------------------------------
local HIGHLIGHT_SECS = 6
local highlight -- { inst, untilT }
function ns.EntranceHighlighted(inst, insts)
  if not (highlight ~= nil and Now() < highlight.untilT) then return false end
  if highlight.inst == inst then return true end
  for _, i in ipairs(insts or {}) do if i == highlight.inst then return true end end
  return false
end
function ns.ShowEntranceOnMap(inst)
  local m = ns.DungeonEntrance(inst)
  if not m then return false end
  if ns.True(ns.Value(InCombatLockdown)) then
    ns.Print(L["The world map cannot be opened in combat."])
    return false
  end
  local opened = false
  if type(OpenWorldMap) == "function" then opened = pcall(OpenWorldMap, m) end
  local wm = WorldMapFrame
  local shown = wm and type(wm.IsShown) == "function" and ns.True(ns.Value(wm.IsShown, wm))
  if shown and type(wm.SetMapID) == "function" and ns.Value(wm.GetMapID, wm) ~= m then pcall(wm.SetMapID, wm, m) end
  if not (opened or shown) then
    ns.Print(L["The world map could not be opened."])
    return false
  end
  highlight = { inst = inst, untilT = Now() + HIGHLIGHT_SECS }
  if ns.RefreshPins then ns.RefreshPins() end
  ns.After(HIGHLIGHT_SECS + 0.1, function()
    if highlight and Now() >= highlight.untilT then
      highlight = nil
      if ns.RefreshPins then ns.RefreshPins() end
    end
  end)
  return true
end

-- /qd dungeonlevels: every dungeon with its table range, the game's range and the entrance, as text to copy.
function ns.DungeonLevelReport()
  local insts = {}
  for inst in pairs(D) do insts[#insts + 1] = inst end
  table.sort(insts, function(a, b)
    local la, lb = ns.DungeonLevelRange(a) or 99, ns.DungeonLevelRange(b) or 99
    if la ~= lb then return la < lb end
    return a < b
  end)
  local out = {}
  for _, inst in ipairs(insts) do
    local tlo, thi = ns.DungeonTableRange(inst)
    local glo, ghi = ns.DungeonGameRange(inst)
    local m, x, y, src = ns.DungeonEntrance(inst)
    -- (round 8) and where its picture comes from (journal, lfg, known, icon, failed, none)
    local pic, tex = ns.DungeonIconSource(inst)
    if pic == "icon" then pic = pic .. " " .. tostring(tex):gsub("^Interface\\Icons\\", "") end
    out[#out + 1] = ("%d %s: data %s, game %s, entrance %s, picture %s"):format(inst, tostring(ns.DungeonName(inst)),
      tlo and ("%d-%d"):format(tlo, thi) or "none", glo and (ghi and ("%d-%d"):format(glo, ghi) or ("%d-?"):format(glo)) or "none",
      m and (("%d %.1f %.1f (%s)"):format(m, x * 100, y * 100, src) .. (#ns.DungeonEntrances(inst) > 1 and (" +" .. (#ns.DungeonEntrances(inst) - 1)) or "")) or "none", pic)
  end
  local gs, es, is = ns.DungeonGameLevelStats(), ejStats, iconStats
  out[#out + 1] = ("game: %d activities, %d matched; journal: %d zones, %d entrances, %d matched"):format(gs.activities, gs.matched,
    es.zones, es.entrances, es.matched)
  out[#out + 1] = ("pictures: journal %d, lfg %d, known %d, icon %d, none %d, failed %d"):format(is.journal, is.lfg, is.known, is.icon,
    is.none, is.failed)
  -- (1.3.6) entrances learned in the game
  local ls = ns.EntranceLearnStats and ns.EntranceLearnStats()
  if ls then
    local own, shared = 0, 0
    for inst in pairs(D) do
      for _, p in ipairs(ns.DungeonEntrances(inst)) do
        if p[6] then own = own + 1 end
        if (p[5] or 0) > 0 then shared = shared + 1 end
      end
    end
    out[#out + 1] = ("entrances learned: %d this session, %d confirmed listed ones; own %d, confirmed by others %d; last skip %s; spots %d"):format(
      ls.learned, ls.confirmed, own, shared, tostring(ls.last), ls.samples)
  end
  return table.concat(out, "\n")
end
function ns.OpenDungeonLevels()
  return ns.ShowText(L["Dungeon levels"], L["The data's and the game's level range of every dungeon, and its entrance. Ctrl+A selects all, Ctrl+C copies."], ns.DungeonLevelReport())
end

function ns.DungeonQuestIDs(inst)
  Index()
  return byDungeon[inst] or {}
end

-- The dungeon the player is in: instanceID or nil (map of the player or one
-- of its parents is a dungeon map of the data).
-- (21.11.2026, Ruckler) kept until the zone changes (the quest list asks every second): ZONE_CHANGED_NEW_AREA,
-- ZONE_CHANGED_INDOORS, PLAYER_ENTERING_WORLD; an empty answer (map not known yet) is asked again after 2 seconds.
-- Only inside a protected call (event, timer, UI part), like DonData's log values
local hereKnown, hereInst, hereAt = false, nil, nil
for _, e in ipairs({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED", "PLAYER_ENTERING_WORLD" }) do
  ns.On(e, function() hereKnown = false end)
end
function ns.ForgetCurrentDungeon() hereKnown = false end -- (tests)
local ReadCurrentDungeon
function ns.CurrentDungeon()
  if not (ns.InScope and ns.InScope()) then return ReadCurrentDungeon() end -- (tests, other addons: read directly)
  local now = Now()
  if hereKnown and (hereInst or (hereAt and now - hereAt >= 0 and now - hereAt < 2)) then return hereInst end
  hereInst, hereKnown, hereAt = ReadCurrentDungeon(), true, now
  return hereInst
end
function ReadCurrentDungeon()
  Index()
  local m = C_Map and ns.Num(ns.Value(C_Map.GetBestMapForUnit, "player"))
  for _ = 1, 4 do
    if not m or m <= 0 then break end
    if byUiMap[m] then return byUiMap[m] end
    local info = ns.Value(C_Map.GetMapInfo, m)
    m = type(info) == "table" and ns.Num(info.parentMapID) or nil
  end
  -- fallback in an instance: its instance map (8th value of GetInstanceInfo), then its name against the dungeon names
  -- (client or English, with or without a leading "The ")
  -- (21.11.2026, Daniel in Hall of Thanes: no uiMap, the game names it "The Hall of Thanes", instance map 3065.) The new
  -- Forever dungeons have ATT's ID as their instance map; the classic ones go through GAME_MAP (journal -> instance map),
  -- and a classic journal ID is never taken as an instance map (BRD's map 230 is Dire Maul's journal ID).
  if not ns.True(ns.Value(IsInInstance)) then return nil end
  local ok, name, _, _, _, _, _, _, imap = false, nil
  if type(GetInstanceInfo) == "function" then ok, name, _, _, _, _, _, _, imap = pcall(GetInstanceInfo) end
  if not ok then return nil end
  imap = imap ~= nil and ns.Usable(imap) and ns.Num(imap) or nil
  if imap then
    for inst, m in pairs(GAME_MAP) do
      if m == imap and byDungeon[inst] then return inst end
    end
    if D[imap] and not GAME_MAP[imap] and byDungeon[imap] then return imap end
  end
  if type(name) ~= "string" or not ns.Usable(name) or name == "" then return nil end
  local bare = name:gsub("^[Tt]he ", "")
  for inst, d in pairs(D) do
    if byDungeon[inst] then
      local n1, n2 = d[NAME_EN], ns.DungeonName(inst)
      if name == n1 or name == n2 or bare == n1 or bare == n2 then return inst end
    end
  end
end

-- Objective progress of a quest in the log as short text ("3/8, 0/1"), or nil.
local function Progress(questID)
  local parts = {}
  for _, o in ipairs(ns.ClientObjectives(questID)) do
    if type(o) == "table" then
      local f, r = ns.Num(o.numFulfilled), ns.Num(o.numRequired)
      if f and r and r > 0 then parts[#parts + 1] = ns.Fraction(f, r) end
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
  for _, p in ipairs(ns.PartyProgress(id)) do out[#out + 1] = L["%s %s (player and quest state)"]:format(p.text or p.name, ns.PartyStateText(p)) end
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
      local lo, hi = ns.DungeonLevelRange(inst)
      list[#list + 1] = { inst = inst, name = ns.DungeonName(inst), level = lo or 0, maxLevel = hi,
        inLog = inLog, available = available, group = group }
    end
  end
  table.sort(list, function(a, b)
    if a.level ~= b.level then return a.level < b.level end
    return tostring(a.name) < tostring(b.name)
  end)
  return list
end

-- (21.11.2026, Ruckler) the quests of one dungeon you can pick up: the overview's "available" of that dungeon alone (the
-- same rule and order), for the quest list inside (it read all some 600 dungeon quests). log: { [questID] = true } or nil
function ns.DungeonAvailable(inst, log)
  Index()
  local out = {}
  if not log then
    log = {}
    for _, info in ipairs(ns.QuestLogEntries()) do log[info.questID] = true end
  end
  local level = ns.PlayerLevel()
  for _, id in ipairs(byDungeon[inst] or {}) do
    local minLevel = Q[id][LEVEL]
    if not log[id] and not (level and minLevel and minLevel > level) and ns.ShowAsAvailable(id) then
      out[#out + 1] = id
    end
  end
  return out
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
  ns.EnsureArrow() -- (review 3) not a second arrow next to the list's compass
  ns.SetArrowTarget(m, x, y, label)
  return true
end

-- Tooltip lines for the panel row: dungeon header, then its quests.
function ns.DungeonTooltipLines(overview)
  local lines = {}
  for _, d in ipairs(overview or ns.DungeonOverview()) do
    local head = d.name
    if d.level > 0 then head = head .. " " .. L["(level %d-%d)"]:format(d.level, d.maxLevel or d.level) end -- (1.3.5) the range
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
      local who = ns.PartyNamesText and ns.PartyNamesText(id) or {}
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
      local who = ns.PartyNamesText and ns.PartyNamesText(id) or {}
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
