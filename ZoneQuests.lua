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
-- seen in Forever are left out. Pages of PAGE_SIZE lines (back / forward in
-- the title bar).
---------------------------------------------------------------------------
local PAGE_SIZE = 20
local MAX_TOOLTIP = 12
local win
local page = 1
local shownMap
local lastSig

-- status groups, in display order
local GROUPS = { "log", "available", "later", "done" }
local GROUP_TITLE = { log = "In your log", available = "Available", later = "Later", done = "Done" }

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

local function MapName(mapID)
  local info = mapID and ns.Value(C_Map.GetMapInfo, mapID)
  local name = type(info) == "table" and info.name
  if type(name) == "string" and ns.Usable(name) and name ~= "" then return name end
  return mapID and ("Map " .. mapID) or "?"
end

---------------------------------------------------------------------------
-- Status of one quest: group, text, colour, sort level; nil = not listed
---------------------------------------------------------------------------
function ns.ZoneQuestStatus(questID)
  if ns.IsQuestDone(questID) then return "done", L["completed"], "good" end
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
  -- only in ATT's old data and never seen in Forever: probably gone
  if ns.QuestOnlyInOldData(questID) and not confirmed and not (ns.db.learned and ns.db.learned[questID]) then return nil end
  if client or ns.CanTakeQuest(questID) then
    if ns.IsLowLevelQuest(questID) then return "available", L["low level"], "textHint" end
    if not confirmed and ns.UnconfirmedNoLevel and ns.UnconfirmedNoLevel(questID) then
      return "later", L["level unknown"], "textHint"
    end
    return "available", L["available"], "accent"
  end
  -- why not (yet)
  local level, player = ns.QuestLevel(questID), ns.PlayerLevel()
  if level and player and level > player then return "later", L["from level %d"]:format(level), "textHint" end
  local pre = ns.MissingPrereq(questID)
  if pre then return "later", L["after: %s"]:format(ns.QuestTitle(pre)), "textHint" end
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
    local group, text, color = ns.ZoneQuestStatus(id)
    if group then
      out[#out + 1] = { questID = id, group = group, text = text, color = color,
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

local function Counts(list)
  local c = { log = 0, available = 0, later = 0, done = 0 }
  for _, e in ipairs(list) do c[e.group] = c[e.group] + 1 end
  return c
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

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function Tooltip(e)
  return function()
    local lines = {}
    local level = ns.QuestLevel(e.questID)
    lines[#lines + 1] = { L["Level"], level and tostring(level) or L["unknown"], level and nil or "textHint" }
    lines[#lines + 1] = { L["Status"], e.text, e.color }
    local givers = ns.QuestGiverIDs(e.questID)
    local giver = givers and ns.CreatureName(givers[1])
    local learned = ns.db.learned and ns.db.learned[e.questID]
    giver = giver or (learned and learned.start and learned.start.npc)
    if giver then lines[#lines + 1] = { L["Quest giver"], giver } end
    local m, x, y = ns.QuestStart(e.questID)
    if m and x then lines[#lines + 1] = { L["Location"], ("%s %.1f, %.1f"):format(MapName(m), x, y) } end
    if ns.QuestFlags(e.questID):find("b", 1, true) then lines[#lines + 1] = { L["Breadcrumb quest"] } end
    local follow = #(ns.FollowUpQuests(e.questID) or {})
    if follow > 0 then lines[#lines + 1] = { L["Chain"], L["%d follow-up quests known"]:format(follow) } end
    return ns.QuestTitle(e.questID), lines,
      L["Click: arrow and mark on the map. Shift-click: also open the map."]
  end
end

local function Summary(list, c)
  return L["%d done, %d in log, %d available, %d later"]:format(c.done, c.log, c.available, c.later)
end

local function Build()
  local mapID = CurrentZone()
  local list = mapID and ns.ZoneQuestList(mapID) or {}
  local pages = math.max(1, math.ceil(#list / PAGE_SIZE))
  if mapID ~= shownMap then page = 1 shownMap = mapID end
  if page > pages then page = pages end
  if page < 1 then page = 1 end
  local c = Counts(list)
  local focusID = ns.zoneFocus and ns.zoneFocus.questID
  -- signature: rebuild only when something visible changed
  local parts = { tostring(mapID), page, tostring(focusID), tostring(ns.PlayerLevel()) }
  for _, e in ipairs(list) do parts[#parts + 1] = e.questID .. e.group .. tostring(e.text) .. tostring(e.title) end
  local sig = table.concat(parts, ",")
  if sig == lastSig and win:IsShown() then return end
  lastSig = sig

  win:SetTitle(Style.Wordmark("Quest", "don") .. Style.Colorize("  " .. MapName(mapID), "textSecondary")
    .. (pages > 1 and Style.Colorize(("  %d/%d"):format(page, pages), "textHint") or ""))
  local back, fwd = win:GetButton("back"), win:GetButton("forward")
  if back then back:SetEnabled(page > 1) end
  if fwd then fwd:SetEnabled(page < pages) end

  win:ClearRows()
  local sum = Style.Row(win)
  Style.KeyValue(sum, L["Quests of the zone"], Style.Number(#list))
  sum:SetTooltip(function() return MapName(mapID), { { Summary(list, c) } },
    L["Shows the zone of the open world map, else yours."] end)
  if #list == 0 then
    local row = Style.Row(win)
    row:SetText(L["No quests known for this zone."], "textHint")
    Style.Relayout(win)
    return
  end
  local first, last = (page - 1) * PAGE_SIZE + 1, math.min(#list, page * PAGE_SIZE)
  local group
  for i = first, last do
    local e = list[i]
    if e.group ~= group then
      group = e.group
      Style.Header(win, L[GROUP_TITLE[group]] .. Style.Colorize(("  %d"):format(c[group]), "textHint"))
    end
    local row = Style.Row(win)
    local title = ns.QuestLevelTag(e.questID) .. e.title
    if e.group == "done" or e.color == "textHint" then
      -- done and later: the whole line quiet (the level tag without its colour)
      local plain = (ns.QuestLevelTag(e.questID):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
      title = Style.Colorize(plain .. e.title, "textHint")
    end
    row:SetText(title, "textPrimary")
    row:SetValue(e.text, e.color)
    if e.questID == focusID then row:SetActive(true) end
    row:SetTooltip(Tooltip(e))
    row:SetOnClick(function() Focus(e, ns.True(ns.Value(IsShiftKeyDown))) end)
  end
  Style.Relayout(win)
end

function ns.UpdateZoneQuests(force)
  if not win or not win:IsShown() then return end
  if force then lastSig = nil end
  Build()
end

local function Create()
  win = Style.Panel("QuestdonZoneQuests", UIParent, {
    title = Style.Wordmark("Quest", "don"),
    width = 340,
    close = true,
    closeTooltip = L["Hide window"],
    get = function(key)
      if key == "pos" then return ns.db.zoneQuestsPos end
      if key == "scale" then return ns.db.panelScale end
      if key == "alpha" then return ns.db.panelAlpha end
      if key == "locked" then return false end
    end,
    set = function(key, value) if key == "pos" then ns.db.zoneQuestsPos = value end end,
    defaultPoint = { "TOPRIGHT", "TOPRIGHT", -560, -220 },
    onClose = function(p)
      ns.zoneFocus = nil
      if ns.RefreshPins then ns.RefreshPins() end
      p:FadeOut()
    end,
    buttons = {
      { key = "forward", kind = "forward", tooltip = L["Next page"],
        onClick = function() page = page + 1 ns.UpdateZoneQuests(true) end },
      { key = "back", kind = "back", tooltip = L["Previous page"],
        onClick = function() page = page - 1 ns.UpdateZoneQuests(true) end },
    },
  })
  win:Hide()
  -- the world map opened, closed or shows another zone: follow it. Our own
  -- frame looks twice a second while the window is open (no hooks on
  -- Blizzard frames, see Core.lua).
  local watch, elapsed, last = CreateFrame("Frame", nil, win), 0, nil
  watch:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + (tonumber(dt) or 0)
    if elapsed < 0.5 then return end
    elapsed = 0
    local key = WorldMapFrame and WorldMapFrame:IsShown() and tostring(ns.Value(WorldMapFrame.GetMapID, WorldMapFrame)) or "-"
    if key ~= last then
      last = key
      ns.SafeCall("zone quests", ns.UpdateZoneQuests)
    end
  end)
end

function ns.ToggleZoneQuests()
  if not win then Create() end
  if win:IsShown() then
    ns.zoneFocus = nil
    if ns.RefreshPins then ns.RefreshPins() end
    win:FadeOut()
    return
  end
  lastSig = nil
  win:FadeIn()
  Build()
end
function ns.ZoneQuestsFrame() return win end

ns.RegisterRefresh("zonequests", function() ns.UpdateZoneQuests() end)
local function Queue() if win and win:IsShown() then ns.QueueRefresh("zonequests") end end
ns.On("QUEST_LOG_UPDATE", Queue)
ns.On("QUEST_TURNED_IN", Queue)
ns.On("PLAYER_LEVEL_UP", Queue)
ns.On("ZONE_CHANGED_NEW_AREA", Queue)
ns.On("QUEST_DATA_LOAD_RESULT", Queue)
