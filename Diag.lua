local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- /qd diag: a compact report for the first tests on the Forever client.
-- Which APIs exist, what a few safe live probes return, and the errors the
-- guard in Core.lua caught. No character, realm, guild, NPC or quest names:
-- only versions, IDs, counts and true/false.
---------------------------------------------------------------------------

-- Look up "C_QuestLog.IsFailed" style paths without erroring.
local function Lookup(path)
  local v = _G
  for part in path:gmatch("[^%.]+") do
    if type(v) ~= "table" then return nil end
    local ok, nextV = pcall(function() return v[part] end)
    if not ok then return nil end
    v = nextV
  end
  return v
end

-- APIs this addon depends on, with a fallback where they are missing.
local APIS = {
  "C_QuestLog.IsFailed", "C_QuestLog.IsQuestTrivial", "C_QuestLog.GetMaxNumQuestsCanAccept",
  "C_QuestLog.IsComplete", "C_QuestLog.GetNextWaypoint", "C_QuestLog.GetQuestWatchType",
  "C_QuestLine.GetAvailableQuestLines", "C_SuperTrack.GetSuperTrackedQuestID",
  "UnitIsPlayer", "UnitGUID", "UnitXP", "GetXPExhaustion", "GetPlayerFacing",
  "canaccessvalue", "issecretvalue",
  "C_Map.GetBestMapForUnit", "C_Map.GetPlayerMapPosition", "C_Map.GetWorldPosFromMapPos", "CreateVector2D",
  "WorldMapFrame", "MapCanvasDataProviderMixin", "MapCanvasPinMixin", "BaseMapPoiPinMixin.CreateSubPin",
  "TooltipDataProcessor.AddTooltipPostCall", "Enum.TooltipDataType.Unit",
  "GetQuestLogRewardXP", "GetQuestLogRewardMoney", "GetNumQuestLogRewards", "GetQuestLogRewardInfo",
  "GetNumQuestLogChoices", "GetQuestLogChoiceInfo", "GetNumQuestChoices", "GetQuestMoneyToGet",
  "GetQuestLogSpecialItemInfo", "C_Container.GetContainerItemQuestInfo",
  "C_AddOns.GetAddOnMetadata", "C_AddOns.IsAddOnLoaded", "date", "debugstack",
  "Settings.RegisterAddOnSetting", "CreateSettingsButtonInitializer",
  "BackdropTemplateMixin", "UISpecialFrames",
  "C_ChatInfo.SendAddonMessage", "C_ChatInfo.RegisterAddonMessagePrefix", "C_ChatInfo.InChatMessagingLockdown",
  "GetNumGroupMembers", "Ambiguate",
}

local function YesNo(v) return v and "true" or "false" end

-- One probe: name, function returning a short text. Errors become "error".
local function Probe(out, name, fn)
  local ok, result = pcall(fn)
  if not ok then
    result = "error"
  elseif result == nil then
    result = "nil"
  end
  out[#out + 1] = ("%s: %s"):format(name, tostring(result))
end

-- What kind of value an API returned: "number", "secret", "nil", ...
local function Kind(v)
  if v == nil then return "nil" end
  if not ns.Usable(v) then return "secret" end
  return type(v)
end

local function Count(t)
  local n = 0
  for _ in pairs(type(t) == "table" and t or {}) do n = n + 1 end
  return n
end

function ns.BuildDiag()
  local out = { "Questdon diagnostics" }
  out[#out + 1] = "version: " .. ns.Version()
  Probe(out, "client", function()
    local version, build, _, toc = GetBuildInfo()
    return ("%s build %s interface %s"):format(tostring(version), tostring(build), tostring(toc))
  end)
  out[#out + 1] = "locale: " .. (ns.Locale and ns.Locale() or "?")
  Probe(out, "project", function()
    local id = WOW_PROJECT_ID
    local main = WOW_PROJECT_MAINLINE
    return ("%s (mainline %s)"):format(tostring(id), tostring(main))
  end)
  out[#out + 1] = "date: " .. (ns.Today and ns.Today() or "?")

  out[#out + 1] = "# APIs"
  local missing = {}
  for _, path in ipairs(APIS) do
    if Lookup(path) == nil then missing[#missing + 1] = path end
  end
  out[#out + 1] = ("present %d of %d"):format(#APIS - #missing, #APIS)
  out[#out + 1] = "missing: " .. (#missing > 0 and table.concat(missing, ", ") or "none")

  out[#out + 1] = "# Probes"
  Probe(out, "UnitXP", function() return Kind(UnitXP("player")) end)
  Probe(out, "UnitXPMax", function() return Kind(UnitXPMax("player")) end)
  Probe(out, "UnitLevel", function() return Kind(UnitLevel("player")) end)
  Probe(out, "UnitGUID player", function() return Kind(UnitGUID("player")) end)
  Probe(out, "npc unit", function()
    -- only meaningful with a quest dialog open
    if not UnitExists("npc") then return "none" end
    local guid = UnitGUID("npc")
    local id = ns.CreatureIDFromGUID and ns.CreatureIDFromGUID(guid)
    return ("guid %s, creature id %s, UnitIsPlayer %s"):format(Kind(guid), id and "yes" or "no",
      UnitIsPlayer and Kind(UnitIsPlayer("npc")) or "missing")
  end)
  Probe(out, "map", function() return ns.Num(ns.Value(C_Map.GetBestMapForUnit, "player")) or "none" end)
  Probe(out, "position", function()
    local map, x, y = ns.PlayerPosition()
    if not map then return "none" end
    local continent = ns.WorldPos and ns.WorldPos(map, x, y)
    return ("yes, world position %s"):format(continent and ("yes (continent " .. tostring(continent) .. ")") or "no")
  end)
  Probe(out, "facing", function() return Kind(GetPlayerFacing and GetPlayerFacing()) end)
  Probe(out, "quests in log", function()
    local entries = ns.QuestLogEntries()
    local max = ns.Num(ns.Value(C_QuestLog.GetMaxNumQuestsCanAccept))
    return ("%d, max %s, full %s"):format(#entries, max and tostring(max) or "unknown", YesNo(ns.QuestLogFull()))
  end)
  Probe(out, "quest states", function()
    local entries = ns.QuestLogEntries()
    local complete, failed, trivial, trivialKind = 0, 0, 0, "n/a"
    for _, info in ipairs(entries) do
      if ns.IsQuestComplete(info.questID) then complete = complete + 1 end
      if ns.IsQuestFailed(info.questID) then failed = failed + 1 end
      if C_QuestLog.IsQuestTrivial then
        local ok, v = pcall(C_QuestLog.IsQuestTrivial, info.questID)
        trivialKind = ok and Kind(v) or "error"
        if ok and ns.True(v) then trivial = trivial + 1 end
      end
    end
    return ("complete %d, failed %d, trivial %d (IsQuestTrivial returns %s)"):format(complete, failed, trivial, trivialKind)
  end)
  Probe(out, "quest rewards", function()
    local entries = ns.QuestLogEntries()
    local first = entries[1]
    if not first then return "no quest in log" end
    return ("xp %s, money %s"):format(Kind(GetQuestLogRewardXP and GetQuestLogRewardXP(first.questID)),
      Kind(GetQuestLogRewardMoney and GetQuestLogRewardMoney(first.questID)))
  end)
  Probe(out, "super tracked", function()
    local id = ns.Num(ns.Value(C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID))
    return id and (id > 0 and "yes" or "no") or "unknown"
  end)
  Probe(out, "map pins", function() return ns.MapPinsState and ns.MapPinsState() or "?" end)
  Probe(out, "minimap pins", function() return ns.MinimapPinsState and ns.MinimapPinsState() or "?" end)
  Probe(out, "nameplate icons", function() return ns.NameplateState and ns.NameplateState() or "?" end)
  -- (1.25) one ! per quest giver: merged by giver, left to the game
  Probe(out, "duplicate givers", function()
    local d = ns.DuplicatePinStats and ns.DuplicatePinStats() or {}
    return ("skip where the game shows ! %s; last build: left to the game %d, merged same giver %d; total left %d, merged %d"):format(
      ns.db.skipGameGivers and "on" or "off", d.lastSuppressed or 0, d.lastMerged or 0, d.suppressed or 0, d.merged or 0)
  end)
  -- (1.27) target button (macro of learned mob names) and waypoint export
  Probe(out, "target button", function()
    local t = ns.TargetButtonState and ns.TargetButtonState() or {}
    local known = 0
    for _ in pairs(ns.db.mobNames or {}) do known = known + 1 end
    return ("%s; names learned %d; tracked quest %s, names in macro %d, %d of %d bytes"):format(
      ns.db.targetButton and "on" or "off", known, tostring(t.questID or "none"), t.names and #t.names or 0,
      t.bytes or 0, ns.TARGET_MACRO_LIMIT or 255)
  end)
  Probe(out, "waypoint export", function()
    local w = ns.WaypointState and ns.WaypointState() or {}
    return ("blizzard %s (pin set %s), TomTom %s (%s, waypoint set %s); C_Map.SetUserWaypoint %s, TomTom %s"):format(
      ns.db.exportBlizzardWaypoint and "on" or "off", w.blizzard and "yes" or "no",
      ns.db.exportTomTom and "on" or "off", type(TomTom) == "table" and "installed" or "not installed", w.tomtom and "yes" or "no",
      (C_Map and C_Map.SetUserWaypoint) and "present" or "missing", type(TomTom) == "table" and "present" or "missing")
  end)
  -- (1.25) arrow: nearest spot and objective area of the tracked quest
  Probe(out, "arrow area", function()
    local a = ns.ArrowAreaState and ns.ArrowAreaState() or {}
    local st = ns.ArrowAreaStats and ns.ArrowAreaStats() or {}
    local t = ns.ArrowTarget and ns.ArrowTarget()
    return ("target %s, spots %d, in area %s (%s), nearest %s yards; checks %d, mob seen %d, entered %d, secret guid %d"):format(
      t and (t.points and "objective" or "other") or "none", t and t.points and #t.points or 0,
      a.inside and "yes" or "no", tostring(a.reason or "-"), a.dist and tostring(math.floor(a.dist + 0.5)) or "?",
      st.checks or 0, st.mobs or 0, st.entered or 0, st.secret or 0)
  end)
  Probe(out, "quest levels", function() return ns.LevelOptionsState and ns.LevelOptionsState() or "?" end)
  -- (1.24) where "available" comes from: client quest lines, quest givers, data
  Probe(out, "quest availability", function()
    local mapID = ns.Num(ns.Value(C_Map and C_Map.GetBestMapForUnit, "player"))
    return ns.AvailabilityState and ns.AvailabilityState(mapID) or "?"
  end)
  -- (1.23) one batched refresh for all quest displays, read scopes
  Probe(out, "refresh", function()
    local r, sc = ns.RefreshStats and ns.RefreshStats() or {}, ns.ScopeStats and ns.ScopeStats() or {}
    return ("batches %d, parts %d, scopes %d"):format(r.flushes or 0, r.parts or 0, sc.scopes or 0)
  end)
  Probe(out, "unit tooltips", function() return YesNo(ns.tooltipHooked) end)
  Probe(out, "settings page", function() return YesNo(ns.settingsCategory) end)
  -- (1.24) The text window needs no Blizzard template any more (own scroll
  -- frame, the kit's close button). Before, this line was read before the
  -- window was built for the first time and said "false, false".
  Probe(out, "window templates", function()
    local p = ns.windowParts or {}
    local function Template(name)
      local get = C_XMLUtil and C_XMLUtil.GetTemplateInfo
      if type(get) ~= "function" then return "unknown" end
      local ok, info = pcall(get, name)
      return ok and info ~= nil and "yes" or "no"
    end
    return ("none needed; text window %s, scroll own, close %s; client has UIPanelScrollFrameTemplate %s, UIPanelCloseButton %s"):format(
      p.built and "built" or "not built yet", p.built and YesNo(p.closeButton) or "kit",
      Template("UIPanelScrollFrameTemplate"), Template("UIPanelCloseButton"))
  end)
  Probe(out, "style kit", function()
    local st = ns.Style or {}
    local panel = ns.PanelFrame and ns.PanelFrame()
    return ("v%s, panel %s, scale %.2f, alpha %.2f, locked %s, collapsed %s"):format(tostring(st.VERSION or "?"),
      panel and (panel:IsShown() and "shown" or "hidden") or "missing", tonumber(ns.db.panelScale) or 1,
      tonumber(ns.db.panelAlpha) or 0, YesNo(ns.db.panelLocked), YesNo(ns.db.panelCollapsed))
  end)
  Probe(out, "Questie", function()
    if not ns.AddOnLoaded("Questie") then return "not loaded" end
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local v = ns.Value(get, "Questie", "Version")
    return ("loaded %s, QuestieDB %s, priority %s"):format(type(v) == "string" and v or "?",
      YesNo(type(LibQuestieDB) == "table"), YesNo(ns.db.questieFirst))
  end)
  Probe(out, "ATT data", function()
    local meta = ns.ATT_META or {}
    return ("%d quests (%s from zzOLD), %d with objectives, %d creatures%s"):format(Count(ns.ATT_QUESTS),
      tostring(ns.Num(meta.fromOld) or "?"), Count(ns.ATT_OBJECTIVES),
      Count(ns.ATT_CREATURES), type(meta.commit) == "string" and (", ATT " .. meta.commit:sub(1, 8)) or "")
  end)
  Probe(out, "quest existence", function()
    -- server answers to RequestLoadQuestByID (Exists.lua); zzOLD = from ATT's older data
    local c = ns.QuestExistsCounts()
    local old = 0
    for _, id in ipairs(ns.MissingQuestIDs()) do
      local q = ns.ATT_QUESTS and ns.ATT_QUESTS[id]
      if q and type(q[14]) == "string" and q[14]:find("o", 1, true) then old = old + 1 end
    end
    return ("confirmed %d, nonexistent %d (zzOLD %d), pending %d, no answer %d, recheck %d, build %s"):format(
      c.confirmed, c.missing, old, c.pending, c.noAnswer, c.recheck, tostring(ns.db.questExistsBuild or "?"))
  end)
  Probe(out, "learned", function()
    local spots = 0
    for _, objs in pairs(ns.db.learnedObj or {}) do
      for _, s in pairs(type(objs) == "table" and objs or {}) do
        if type(s) == "table" then spots = spots + math.floor(#s / 3) end
      end
    end
    local follow = 0
    for _, e in pairs(ns.db.learned or {}) do
      if type(e) == "table" and type(e.after) == "table" and next(e.after) then follow = follow + 1 end
    end
    -- (1.0.1) follow-ups, credit sources, drops, item starts
    return ("%d quests, %d objective spots, %d follow-ups, credit in %d quests, drops of %d items, %d item starts"):format(
      Count(ns.db.learned), spots, follow, Count(ns.db.learnedCredit), Count(ns.db.learnedDrops), Count(ns.db.learnedItemStarts))
  end)

  Probe(out, "dungeon quests", function()
    local inLog, toTake = ns.DungeonCounts()
    local meta = ns.ATT_META or {}
    return ("%d in data, %d dungeons, in log %d, to pick up %d, current dungeon %s"):format(ns.Num(meta.dungeonQuests) or 0,
      Count(ns.ATT_DUNGEONS), inLog, toTake, tostring(ns.CurrentDungeon() or "none"))
  end)
  Probe(out, "group progress", function() return ns.PartyDiag() end)
  Probe(out, "net test", function() return ns.NetDiag and ns.NetDiag() or "nil" end)
  Probe(out, "sharing", function() return ns.ShareDiag and ns.ShareDiag() or "nil" end)
  out[#out + 1] = "# Blizzard quest POIs"
  Probe(out, "POI APIs", function() return (ns.POIDiag()) end)
  Probe(out, "POI points", function() return select(2, ns.POIDiag()) end)

  out[#out + 1] = "# Quest items in bags (1.0)"
  local okQ, qlines = pcall(ns.QuestItemDiag)
  if okQ and type(qlines) == "table" then
    for _, line in ipairs(qlines) do out[#out + 1] = line end
  else
    out[#out + 1] = "error: " .. tostring(qlines)
  end

  out[#out + 1] = "# Errors"
  local errors = ns.Errors and ns.Errors() or {}
  if #errors == 0 then out[#out + 1] = "none" end
  for i, e in ipairs(errors) do
    out[#out + 1] = ("%d. [%s, %s] x%d %s"):format(i, e.module, e.context, e.count, e.msg)
    if e.stack then out[#out + 1] = "   " .. e.stack end
  end
  return table.concat(out, "\n")
end

function ns.OpenDiag()
  local text = ns.BuildDiag()
  return ns.ShowText(L["Diagnostics"], L["Ctrl+A selects all, Ctrl+C copies. Please add this to bug reports."]
    .. " " .. L["Only numbers: no character, realm or guild names."], text)
end
