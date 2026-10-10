local _, ns = ...
local L = ns.L
local Style = ns.Style

---------------------------------------------------------------------------
-- (1.2) Quests of the zone: every quest that starts in a zone, grouped by
-- what it is for you: in your log, available now, later (with the reason)
-- and done. A window in the family look, opened with the list button in the
-- Questdon title bar or /qd zone.
--
-- The zone is the one the world map shows while it is open, else your own.
-- Click a quest: the arrow points there and the world map marks it (a "!"
-- or "?" at the quest giver, also for done quests and quests for later).
-- Shift-click also opens the world map at that zone.
--
-- Quests other characters cannot do (faction, race, class), quests the
-- server does not know and quests only in ATT's old data that nobody has
-- seen in Forever are left out.
--
-- (1.2.2) The window is the quest book: three tabs, "Journal" (Journal.lua,
-- the personal diary), "Zone" (this list) and "Search". /qd zone opens the
-- zone tab, /qd journal the journal; the list button in the Questdon title
-- bar opens the book on the last tab.
--
-- (1.3) The window itself is in QuestBook.lua (large, zones to pick, chains
-- in one line); this file keeps the list and the status of the quests.
---------------------------------------------------------------------------
-- status groups, in display order
local GROUPS = { "log", "available", "later", "done" }
ns.ZONE_GROUPS = GROUPS
ns.ZONE_GROUP_TITLE = { log = "In your log", available = "Available", later = "Later", done = "Done" }

-- Zone of a map (caves and buildings: the zone around them).
local function ZoneOf(mapID)
  mapID = ns.Num(mapID)
  if not mapID then return nil end
  return ns.MinimapZoneMap and ns.MinimapZoneMap(mapID) or mapID
end

-- The zone to list: the world map's while it is open, else the player's.
local function CurrentZone()
  if WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame.GetMapID then
    local m = ZoneOf(ns.Value(WorldMapFrame.GetMapID, WorldMapFrame))
    if m and #ns.QuestsStartingOnMap(m) > 0 then return m end
  end
  return ZoneOf(ns.Value(C_Map.GetBestMapForUnit, "player"))
end
ns.ZoneQuestsMap = CurrentZone
ns.ZoneOfMap = ZoneOf

local function MapName(mapID)
  local info = mapID and ns.Value(C_Map.GetMapInfo, mapID)
  local name = type(info) == "table" and info.name
  if type(name) == "string" and ns.Usable(name) and name ~= "" then return name end
  return mapID and ("Map " .. mapID) or "?"
end

---------------------------------------------------------------------------
-- Status of one quest: group, text, colour, unconfirmed; nil = not listed
---------------------------------------------------------------------------
local ZoneStatusFor
function ns.ZoneQuestStatus(questID)
  if ns.IsQuestDone(questID) then
    if ns.DoneElsewhere and ns.DoneElsewhere(questID) then return nil end -- (1.3.4) a variant done in another zone
    return "done", L["completed"], "good"
  end
  if ns.InQuestLog(questID) then
    if ns.IsQuestComplete(questID) then return "log", L["ready to turn in"], "good" end
    return "log", L["in log"], "warning"
  end
  -- quests only Questdon learned (not in the data): the map's rules for them
  if not ns.QuestInData(questID) then
    local ok, why = ns.LearnedQuestAvailable(questID)
    if ok then return "available", L["available"], "accent" end
    if why == "faction" or why == "never" or why == "missing" then return nil end
    return "later", why == "level" and L["not offered at your level"] or L["not yet"], "textHint"
  end
  if not ns.QuestReachable(questID) then return nil end
  if ns.QuestKnownMissing and ns.QuestKnownMissing(questID) then return nil end
  if ns.BreadcrumbObsolete(questID) then return nil end
  local client = ns.ClientAvailability and ns.ClientAvailability(questID) == true
  local confirmed = client or (ns.OfferConfirmed and ns.OfferConfirmed(questID, ns.PlayerLevel()))
  -- only in ATT's old data and not seen in Forever yet. (1.3) Listed unless
  -- the server said it does not exist (QuestKnownMissing above): ATT's
  -- Forever data only covers the zones of the beta so far, most quests of the
  -- higher zones (Ashenvale, Felwood, Tanaris ...) are only in the old data.
  -- The server is asked in the background (Exists.lua); marked "unconfirmed".
  local unconfirmed = ns.QuestOnlyInOldData(questID) and not confirmed and not (ns.db.learned and ns.db.learned[questID])
    and ns.QuestExists(questID) ~= true
  local group, text, color = ZoneStatusFor(questID, client, confirmed)
  return group, text, color, unconfirmed or nil
end

-- The rest of the status (after the checks above).
ZoneStatusFor = function(questID, client, confirmed)
  if client or ns.CanTakeQuest(questID) then
    if ns.IsLowLevelQuest(questID) then return "available", L["low level"], "textHint" end
    if ns.IsRepeatableQuest and ns.IsRepeatableQuest(questID) then return "available", L["repeatable"], "textHint" end -- (1.3.5)
    if not confirmed and ns.UnconfirmedNoLevel and ns.UnconfirmedNoLevel(questID) then
      return "later", L["level unknown"], "textHint"
    end
    return "available", L["available"], "accent"
  end
  -- why not (yet)
  local level, player = ns.QuestLevel(questID), ns.PlayerLevel()
  if level and player and level > player then return "later", L["from level %d"]:format(level), "textHint" end
  local pre = ns.MissingPrereq(questID)
  if pre then return "later", L["after: %s"]:format(ns.QuestTitleWithPart(pre)), "textHint" end -- (1.3.4) with "(1/2)"
  if ns.MissingSkill and ns.MissingSkill(questID) then return "later", L["profession not learned"], "textHint" end
  if ns.IsEventQuest(questID) then return "later", L["event"], "textHint" end
  if ns.NeverOffered and ns.NeverOffered(questID) then return nil end
  if player and ns.NotOfferedLevel and ns.NotOfferedLevel(questID, player) then
    return "later", L["not offered at your level"], "textHint"
  end
  local flags = ns.QuestFlags(questID)
  if flags:find("r", 1, true) then return "later", L["repeatable"], "textHint" end
  return "later", L["not yet"], "textHint"
end

-- All listed quests of a map, sorted: group, level, title.
function ns.ZoneQuestList(mapID)
  local out = {}
  local rank = {}
  for i, g in ipairs(GROUPS) do rank[g] = i end
  for _, id in ipairs(ns.QuestsStartingOnMap(mapID)) do
    local group, text, color, unconfirmed = ns.ZoneQuestStatus(id)
    if group then
      out[#out + 1] = { questID = id, group = group, text = text, color = color, unconfirmed = unconfirmed,
        level = ns.QuestLevel(id) or 0, title = ns.QuestTitle(id) }
    end
  end
  table.sort(out, function(a, b)
    if a.group ~= b.group then return rank[a.group] < rank[b.group] end
    if a.level ~= b.level then return a.level < b.level end
    if a.title ~= b.title then return tostring(a.title) < tostring(b.title) end
    return a.questID < b.questID
  end)
  return out
end

---------------------------------------------------------------------------
-- Where a quest is on the map: start, else turn-in (0-1)
---------------------------------------------------------------------------
local function QuestSpot(e)
  local id = e.questID
  if e.group == "log" then
    -- finished: where to turn it in; else the nearest open objective
    if ns.IsQuestComplete(id) then
      local m, x, y = ns.TurnInPoint(id, true)
      if m then return m, x, y, "turnin" end
    else
      local pts = ns.AllObjectivePoints and ns.AllObjectivePoints(id) or {}
      if pts[1] then return pts[1].mapID, pts[1].x, pts[1].y, "objective" end
    end
  end
  local m, x, y = ns.QuestStart(id)
  if m and x then return m, x / 100, y / 100, "start" end
  local tm, tx, ty = ns.TurnInPoint(id)
  if tm then return tm, tx, ty, "turnin" end
end

-- (1.2) The quest the zone list marks on the world map: { questID, mapID, x, y, group }
ns.zoneFocus = nil
function ns.ZoneFocusPin(mapID)
  local f = ns.zoneFocus
  if not f or f.mapID ~= mapID then return nil end
  -- the status now (accepted, finished, turned in since the click)
  local status, text = ns.ZoneQuestStatus(f.questID)
  if not status then return nil end
  -- "status", not "group": pin.group is the list of a grouped quest giver pin
  return { kind = "focus", questID = f.questID, x = f.x, y = f.y, status = status, statusText = text,
    iconKind = f.what == "turnin" and "turnin" or "available", dimmed = (status == "done" or status == "later") or nil }
end

local function Focus(e, openMap)
  local m, x, y, what = QuestSpot(e)
  if not m then ns.Print(L["No position known for %s."]:format(ns.QuestTitle(e.questID))) return end
  ns.zoneFocus = { questID = e.questID, mapID = m, x = x, y = y, group = e.group, text = e.text, what = what }
  if ns.SetArrowTarget then
    ns.db.arrow = true
    if ns.ApplyArrow then ns.ApplyArrow() end
    ns.SetArrowTarget(m, x, y, ns.QuestTitle(e.questID))
  end
  if openMap and not InCombatLockdown() and OpenWorldMap then pcall(OpenWorldMap, m) end
  if ns.RefreshPins then ns.RefreshPins() end
  ns.UpdateZoneQuests(true)
end

-- (1.2.2) For the journal and the search: arrow and map mark for any quest.
function ns.FocusQuest(questID, openMap)
  local group, text = ns.ZoneQuestStatus(questID)
  Focus({ questID = questID, group = group or "done", text = text }, openMap)
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------
-- Tooltip of a quest row (zone list, chains, search): title, lines, hint.
function ns.ZoneQuestTooltip(e)
  return function()
    local lines = {}
    local level = ns.QuestLevel(e.questID)
    lines[#lines + 1] = { L["Level"], level and tostring(level) or L["unknown"], level and nil or "textHint" }
    lines[#lines + 1] = { L["Status"], e.text, e.color }
    local givers = ns.QuestGiverIDs(e.questID)
    local giver = givers and ns.LocalNpcName(givers[1])
    local learned = ns.db.learned and ns.db.learned[e.questID]
    giver = giver or (learned and learned.start and learned.start.npc)
    if giver then lines[#lines + 1] = { L["Quest giver"], giver } end
    local m, x, y = ns.QuestStart(e.questID)
    if m and x then lines[#lines + 1] = { L["Location"], ("%s %.1f, %.1f"):format(MapName(m), x, y) } end
    if ns.QuestFlags(e.questID):find("b", 1, true) then lines[#lines + 1] = { L["Breadcrumb quest"] } end
    if e.unconfirmed then lines[#lines + 1] = { L["Only in the older quest data. Forever has not confirmed this quest yet, it may be changed or gone."] } end
    local follow = #(ns.FollowUpQuests(e.questID) or {})
    if follow > 0 then lines[#lines + 1] = { L["Chain"], L["%d follow-up quests known"]:format(follow) } end
    return ns.QuestTitle(e.questID), lines,
      L["Click: details. Shift-click: also the arrow and the world map."]
  end
end

